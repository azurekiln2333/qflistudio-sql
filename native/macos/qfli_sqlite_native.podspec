require_relative '../apple/podspec'
Pod::Spec.new do |s|
  QfliSqliteNative.configure(s, :macos, __dir__)
end
