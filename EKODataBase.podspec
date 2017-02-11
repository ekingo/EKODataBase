Pod::Spec.new do |s|
  s.name	 = "EKODataBase"
  s.version      = "0.0.4"
  s.summary      = "SQLite Manager directly deal with Model or Class"

  s.description  = <<-DESC
		When insert Data into SQLite, you don’t need to know SQL,just write your Class(Model),and insert it(or update it),that’s all.
DESC

  s.license      = "MIT"
  s.homepage	 = "https://github.com/ekingo/EKODataBase"
  s.author       = { "ekingo" => "ekingo1987@gmail.com" }

  s.platform     = :ios
  s.platform     = :ios, "7.0"

  s.source       = { :git => "https://github.com/ekingo/EKODataBase.git", :tag => "0.0.4" }

  s.source_files  = "EKODataBase/*","EKODataBase/SQLite/*"
  s.exclude_files = "EKODataBaseTests"

  s.public_header_files = "EKODataBase/EKODataBase.h","EKODataBase/SQLite/EKOSQLiteMgr.h"

  s.frameworks = "Foundation", "UIKit"

  s.library   = "sqlite3"

end
