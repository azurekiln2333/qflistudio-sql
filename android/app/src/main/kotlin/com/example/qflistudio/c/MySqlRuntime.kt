package com.azurekiln.qfli.sqlab

import android.content.Context
import android.system.Os
import org.json.JSONObject
import java.io.DataInputStream
import java.io.File
import java.util.zip.ZipInputStream

internal class MySqlRuntime(private val context: Context) {
    fun prepare(): Map<String, String> {
        val native = File(context.applicationInfo.nativeLibraryDir)
        val server = File(native, "libqfli_mysqld_exec.so")
        val launcher = File(native, "libqfli_mysql_launcher_exec.so")
        val bridge = File(native, "libqfli_mysql_bridge.so")
        val header = DataInputStream(server.inputStream()).use { input ->
            ByteArray(20).also { input.readFully(it) }
        }
        check(header[0] == 127.toByte() && header[1] == 69.toByte() &&
            header[2] == 76.toByte() && header[3] == 70.toByte() &&
            header[4] == 2.toByte() && header[5] == 1.toByte()) { "Invalid Android Oracle server" }
        val machine = (header[18].toInt() and 255) or ((header[19].toInt() and 255) shl 8)
        val abi = when (machine) {
            62 -> "x86_64"
            183 -> "arm64-v8a"
            else -> error("Unsupported Android Oracle ABI: $machine")
        }
        check(server.canExecute() && launcher.canExecute() && bridge.isFile) {
            "Android Oracle native files are missing or not executable"
        }
        val manifest = context.assets.open("mysql-$abi.json").bufferedReader().use {
            JSONObject(it.readText())
        }
        check(manifest.getInt("version") == 1) { "Unsupported Android Oracle resource layout" }
        val id = manifest.getString("id")
        check(id.matches(Regex("${Regex.escape(abi)}-[a-f0-9]{64}")) &&
            manifest.getString("serverVersion") == "8.4.6") { "Invalid Android Oracle resource identity" }
        val resources = File(context.filesDir, "mysql-resources")
        check(resources.isDirectory || resources.mkdirs()) { "Cannot create Oracle resources directory" }
        val home = File(resources, id)
        val marker = File(home, ".qfli-resource-id")
        if (!marker.isFile || marker.readText() != id || !File(home, "share/english/errmsg.sys").isFile ||
            !File(home, "share/icu/icudt77l/unames.icu").isFile) {
            val staging = File(resources, "$id-install")
            check(!staging.exists() || staging.deleteRecursively()) { "Cannot replace Oracle resource staging" }
            check(staging.mkdirs()) { "Cannot create Oracle resource staging" }
            try {
                val root = staging.canonicalPath + File.separator
                ZipInputStream(context.assets.open("mysql-$abi.zip")).use { zip ->
                    var entry = zip.nextEntry
                    while (entry != null) {
                        val file = File(staging, entry.name)
                        check(file.canonicalPath.startsWith(root)) { "Invalid Oracle resource archive path" }
                        if (entry.isDirectory) {
                            check(file.isDirectory || file.mkdirs()) { "Cannot create Oracle resource directory" }
                        } else {
                            check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs()) {
                                "Cannot create Oracle resource parent"
                            }
                            file.outputStream().use { zip.copyTo(it) }
                        }
                        zip.closeEntry()
                        entry = zip.nextEntry
                    }
                }
                check(File(staging, "share/english/errmsg.sys").isFile) { "Oracle messages are missing" }
                check(File(staging, "share/icu/icudt77l/unames.icu").isFile) { "Oracle ICU data is missing" }
                File(staging, ".qfli-resource-id").writeText(id)
                check(!home.exists() || home.deleteRecursively()) { "Cannot replace incomplete Oracle resources" }
                check(staging.renameTo(home)) { "Cannot install Oracle resources" }
            } finally {
                staging.deleteRecursively()
            }
        }
        val data = File(context.filesDir, "mysql-runtime")
        val temporary = File(context.cacheDir, "mysql")
        for (directory in listOf(home, data, temporary)) {
            check(directory.isDirectory || directory.mkdirs()) { "Cannot create Oracle runtime directory" }
            Os.chmod(directory.path, 448)
        }
        return mapOf(
            "bundleDirectory" to home.path,
            "dataDirectory" to data.path,
            "temporaryDirectory" to temporary.path,
            "libraryDirectory" to native.path,
            "serverPath" to server.path,
            "launcherPath" to launcher.path,
            "libraryPath" to bridge.path
        )
    }
}
