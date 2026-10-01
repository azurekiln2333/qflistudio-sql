require 'fileutils'

module QfliSqliteNative
  def self.configure(spec, platform, pod_dir)
    native_dir = File.realpath(File.join(pod_dir, '..'))
    sources = %w[third_party/sqlite/sqlite3.c third_party/sqlite/sqlite3.h src/qfli_sql_bridge.c src/qfli_sql_bridge.h]
    staged = sources.map do |relative|
      source = File.join(native_dir, relative)
      raise "Missing retained SQLite source: #{source}" unless File.file?(source)
      target = File.join('Classes/build/sqlite', File.basename(relative))
      absolute = File.join(pod_dir, target)
      FileUtils.mkdir_p(File.dirname(absolute))
      FileUtils.cp(source, absolute) unless File.file?(absolute) && File.binread(source) == File.binread(absolute)
      target
    end
    spec.name = 'qfli_sqlite_native'
    spec.version = '1.0.0'
    spec.summary = 'Retained upstream SQLite C runtime for QFLISQLab.'
    spec.homepage = 'https://sqlite.org'
    spec.author = 'QFLIStudio'
    spec.license = { :type => 'Public Domain', :text => 'SQLite source retains its upstream public domain notice. The QFLI bridge retains its application license.' }
    spec.source = { :path => '.' }
    spec.source_files = staged
    spec.private_header_files = staged.select { |path| path.end_with?('.h') }
    spec.static_framework = true
    spec.libraries = 'm'
    spec.pod_target_xcconfig = {
      'DEFINES_MODULE' => 'NO',
      'GCC_C_LANGUAGE_STANDARD' => 'gnu99',
      'GCC_SYMBOLS_PRIVATE_EXTERN' => 'NO',
      'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) SQLITE_THREADSAFE=1 SQLITE_DEFAULT_MEMSTATUS=0 SQLITE_DQS=0 SQLITE_OMIT_LOAD_EXTENSION'
    }
    # Retain both C objects when the app links the static pod archive.
    symbols = %w[qfli_sql_execute qfli_sql_result_free sqlite3_open_v2 sqlite3_close
                 sqlite3_busy_timeout sqlite3_prepare_v2 sqlite3_step sqlite3_finalize
                 sqlite3_bind_parameter_count sqlite3_bind_null sqlite3_bind_text
                 sqlite3_column_count sqlite3_column_name sqlite3_column_type
                 sqlite3_column_text sqlite3_column_bytes sqlite3_changes sqlite3_errmsg]
    spec.user_target_xcconfig = {
      'OTHER_LDFLAGS' => '$(inherited) ' + symbols.map { |symbol| "-Wl,-u,_#{symbol}" }.join(' ')
    }
    if platform == :ios
      spec.dependency 'Flutter'
      spec.platform = :ios, '13.0'
    else
      spec.dependency 'FlutterMacOS'
      spec.platform = :osx, '10.15'
    end
  end
end
