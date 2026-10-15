
// Script for compiling build behavior. It is built in the build plug-in and cannot be modified currently.
import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import fs from 'fs';
import path from 'path';

// Stage the versioned runtime before Hvigor discovers native libraries/resources.
// All four libraries are required: the runtime and private preloaded server
// libraries, the launcher, and the private server image the phone host loads.
const mysqlPackage = path.resolve(__dirname, '../../build/mysql-port/package');
if (fs.existsSync(path.join(mysqlPackage, 'rawfile/mysql/runtime.json'))) {
    for (const library of ['libqfli_mysql.so', 'libqfli_mysql_server.so',
        'libqfli_mysql_launcher.so', 'libqfli_mysql_server_proto.so']) {
        const source = path.join(mysqlPackage, 'libs/arm64-v8a', library);
        if (!fs.existsSync(source)) {
            throw new Error(`Oracle MySQL runtime package is incomplete: ${library}`);
        }
    }
    fs.mkdirSync(path.join(__dirname, 'libs/arm64-v8a'), { recursive: true });
    fs.cpSync(path.join(mysqlPackage, 'libs/arm64-v8a'),
        path.join(__dirname, 'libs/arm64-v8a'), { recursive: true });
    fs.mkdirSync(path.join(__dirname, 'src/main/resources/rawfile'), { recursive: true });
    fs.cpSync(path.join(mysqlPackage, 'rawfile/mysql'),
        path.join(__dirname, 'src/main/resources/rawfile/mysql'), { recursive: true });
}
export default {
    system: hapTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins: []        /* Custom plugin to extend the functionality of Hvigor. */
}
