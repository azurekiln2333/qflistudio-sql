import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import { MethodCall, MethodResult } from '@ohos/flutter_ohos';

interface PickerDocument {
  uri: string;
  name: string;
}

export function isPickerMethod(method: string): boolean {
  return method === 'pickDocument' || method === 'saveDocument' ||
    method === 'pickPhotos' || method === 'readUri' || method === 'readSqlUri' ||
    method === 'writeUri';
}

export function handlePickerCall(
  context: common.UIAbilityContext,
  call: MethodCall,
  result: MethodResult,
): void {
  runPickerCall(context, call, result);
}

async function runPickerCall(
  context: common.UIAbilityContext,
  call: MethodCall,
  result: MethodResult,
): Promise<void> {
  try {
    switch (call.method) {
      case 'pickDocument':
        result.success(await pickDocument(context, call));
        return;
      case 'saveDocument':
        result.success(await saveDocument(context, call));
        return;
      case 'pickPhotos':
        result.success(await pickPhotos());
        return;
      case 'readUri':
        result.success(await readUri(call.argument('uri') as string));
        return;
      case 'readSqlUri':
        result.success(await readUri(call.argument('uri') as string, 1024 * 1024));
        return;
      case 'writeUri':
        await writeUri(
          call.argument('uri') as string,
          call.argument('bytes') as Uint8Array,
        );
        result.success(null);
        return;
      default:
        result.notImplemented();
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    result.error('PICKER_ERROR', message, null);
  }
}

async function pickDocument(
  context: common.UIAbilityContext,
  call: MethodCall,
): Promise<PickerDocument | null> {
  const options = new picker.DocumentSelectOptions();
  options.selectMode = call.argument('folder') as boolean
    ? picker.DocumentSelectMode.FOLDER
    : picker.DocumentSelectMode.FILE;
  const extensions = call.argument('extensions') as Array<string>;
  if (extensions != null && extensions.length > 0) {
    options.fileSuffixFilters = extensions.map((extension: string) => {
      const suffix = extension.startsWith('.') ? extension : `.${extension}`;
      return `QFLI files|${suffix}`;
    });
  }
  const uris = await new picker.DocumentViewPicker(context).select(options);
  if (uris.length === 0) return null;
  return { uri: uris[0], name: uriName(uris[0]) };
}

async function saveDocument(
  context: common.UIAbilityContext,
  call: MethodCall,
): Promise<PickerDocument | null> {
  const name = String(call.argument('suggestedName') ?? 'qfli-project.json');
  const dot = name.lastIndexOf('.');
  const suffix = dot > 0 ? name.substring(dot) : '.json';
  const options = new picker.DocumentSaveOptions();
  options.newFileNames = [name];
  options.fileSuffixChoices = [`QFLI files|${suffix}`];
  const uris = await new picker.DocumentViewPicker(context).save(options);
  if (uris.length === 0) return null;
  return { uri: uris[0], name: uriName(uris[0]) };
}

async function pickPhotos(): Promise<Array<PickerDocument>> {
  const options = new photoAccessHelper.PhotoSelectOptions();
  options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  options.maxSelectNumber = 20;
  const selection = await new photoAccessHelper.PhotoViewPicker().select(options);
  const documents: Array<PickerDocument> = [];
  for (const uri of selection.photoUris) {
    documents.push({ uri: uri, name: uriName(uri) });
  }
  return documents;
}

async function readUri(uri: string, maxBytes?: number): Promise<Uint8Array> {
  const file = await fs.open(uri, fs.OpenMode.READ_ONLY);
  try {
    const stat = await fs.stat(file.fd);
    const size = Number(stat.size);
    if (!Number.isSafeInteger(size) || size < 0) throw new Error('文件大小无效');
    if (maxBytes !== undefined && size > maxBytes) throw new Error('SQL 文件超过 1 MiB 上限');
    const bytes = new Uint8Array(size);
    const chunk = new ArrayBuffer(Math.min(size, 64 * 1024));
    let offset = 0;
    while (offset < size) {
      const length = Math.min(chunk.byteLength, size - offset);
      const count = await fs.read(file.fd, chunk, { length: length });
      if (count <= 0 || count > length) throw new Error('文件未完整读取，请重新选择');
      bytes.set(new Uint8Array(chunk, 0, count), offset);
      offset += count;
    }
    const extra = new ArrayBuffer(1);
    if (await fs.read(file.fd, extra, { length: 1 }) !== 0) {
      throw new Error('文件在读取过程中已发生变化，请重新选择');
    }
    return bytes;
  } finally {
    await fs.close(file.fd);
  }
}

async function writeUri(uri: string, bytes: Uint8Array): Promise<void> {
  const file = await fs.open(uri, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try {
    let offset = 0;
    while (offset < bytes.byteLength) {
      const length = Math.min(64 * 1024, bytes.byteLength - offset);
      const chunk = bytes.buffer.slice(bytes.byteOffset + offset, bytes.byteOffset + offset + length);
      const count = await fs.write(file.fd, chunk, { length: length });
      if (count <= 0 || count > length) throw new Error('文件未完整写入');
      offset += count;
    }
    await fs.fsync(file.fd);
  } finally {
    await fs.close(file.fd);
  }
}

function uriName(uri: string): string {
  const slash = uri.lastIndexOf('/');
  return slash >= 0 ? decodeURIComponent(uri.substring(slash + 1)) : uri;
}
