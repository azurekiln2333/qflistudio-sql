require_relative '../apple/podspec'
Pod::Spec.new do |s|
  QfliSqliteNative.configure(s, :ios, __dir__)
end
