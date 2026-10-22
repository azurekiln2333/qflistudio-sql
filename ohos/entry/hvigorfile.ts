
// Script for compiling build behavior. It is built in the build plug-in and cannot be modified currently.
import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import fs from 'fs';
import path from 'path';

// Stage the versioned runtime before Hvigor discovers native libraries/resources.
// All four libraries are required: the runtime and private preloaded server
// libraries, the launcher, and the private server image the phone host loads.
const mysqlPackage = path.resolve(__dirname, '../../build/mysql-port/package');
if (fs.existsSync(path.join(mysqlPackage, 'rawfile/mysql/runtime.json'))) {
    for (const [abi, machine] of [['arm64-v8a', 183], ['x86_64', 62]] as const) {
        const sourceDirectory = path.join(mysqlPackage, 'libs', abi);
        if (!fs.existsSync(sourceDirectory)) continue;
        for (const library of ['libqfli_mysql.so', 'libqfli_mysql_server.so',
            'libqfli_mysql_launcher.so', 'libqfli_mysql_server_proto.so']) {
            const source = path.join(sourceDirectory, library);
            if (!fs.existsSync(source)) {
                throw new Error(`Oracle MySQL ${abi} runtime package is incomplete: ${library}`);
            }
            const header = Buffer.alloc(20);
            const descriptor = fs.openSync(source, 'r');
            let bytes = 0;
            try {
                bytes = fs.readSync(descriptor, header, 0, header.length, 0);
            } finally {
                fs.closeSync(descriptor);
            }
            if (bytes !== 20 || header.readUInt32BE(0) !== 0x7f454c46 ||
                header[4] !== 2 || header[5] !== 1 || header.readUInt16LE(18) !== machine) {
                throw new Error(`Oracle MySQL ${abi} library has the wrong ELF architecture: ${library}`);
            }
        }
        const destination = path.join(__dirname, 'libs', abi);
        fs.mkdirSync(destination, { recursive: true });
        fs.cpSync(sourceDirectory, destination, { recursive: true });
    }
    fs.mkdirSync(path.join(__dirname, 'src/main/resources/rawfile'), { recursive: true });
    fs.cpSync(path.join(mysqlPackage, 'rawfile/mysql'),
        path.join(__dirname, 'src/main/resources/rawfile/mysql'), { recursive: true });
}
export default {
    system: hapTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins: []        /* Custom plugin to extend the functionality of Hvigor. */
}
