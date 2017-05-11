//
//  EKODataBase.h
//  EKODataBase
//
//  Created by kingo on 25/01/2017.
//  Copyright © 2017 XTC. All rights reserved.
//

#import <UIKit/UIKit.h>

//! Project version number for EKODataBase.
FOUNDATION_EXPORT double EKODataBaseVersionNumber;

//! Project version string for EKODataBase.
FOUNDATION_EXPORT const unsigned char EKODataBaseVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <EKODataBase/PublicHeader.h>

//提供通过对象操作SQLite数据库接口
#import <EKODataBase/EKOSQLiteMgr.h>
#import <EKODataBase/EKOSQLiteMgr+Async.h>
