//
//  EKOSQLiteMgr.h
//  EKODataBase
//
//  Created by kingo on 25/01/2017.
//  Copyright © 2017 XTC. All rights reserved.
//

#import <Foundation/Foundation.h>

#define EKODATABASE_ENABLE_ENCRYPT  0

typedef NS_ENUM(NSInteger,EKOSError) {
    EKOSErrorUnknown = -1,
    EKOSErrorNone    = 0,
    
    EKOSErrorEncryptFail            = 1, //设置密码错误
    EKOSErrorEncryptNotSupported    = 2, //不支持数据库加密
    
    EKOSErrorConditionNone          = 3, //未定义条件语句
    
    EKOSErrorPrimaryKeyLack         = 4, //缺少定义的主键
};


/**
 数据库
 默认路径：Library/Cache/EKODataBase/ModelClassName_vX.Y.sdb
 */
@interface EKOSQLiteMgr : NSObject

- (instancetype)initWithDataBaseDir:(NSString *)dir;

#if EKODATABASE_ENABLE_ENCRYPT

/**
 数据库加密处理 [使用到第三方库FMDB/SQLCiper]

 @param dir 数据库文件保存路径【为nil使用默认路径】
 @param key 默认所有类别的加密密钥
 @return 管理器
 */
- (instancetype)initWithDatabBaseDir:(NSString *)dir privateKey:(NSString *)key;

/**
 移除当前数据库密码

 @param key 当前使用的密钥
 @param cls 关联的类【如果为nil则清空所有类密码】
 @return 是否成功
 */
- (EKOSError)removeEncryptKey:(NSString *)key ofModelClass:(Class)cls;

//更改当前模型数据库的密码
- (EKOSError)resetEncryptKey:(NSString *)key withOriginalKey:(NSString *)oKey ofModelClass:(Class)cls;
#endif

// SQLite Operations
//- (BOOL)openDatabase;
//- (void)closeDatabase;


/**
 插入数据库

 @param model 定义好的数据【如果定义了_id字段，同updateModel】
 @return 是否成功
 */
- (EKOSError)insertModel:(id)model;

/**
 插入数据列表到数据库

 @param models 数据列表
 @return 成功与否
 */
- (EKOSError)insertModels:(NSArray *)models;

//插入数据
- (NSArray *)queryByClass:(Class)cls;
- (NSArray *)queryByClass:(Class)cls where:(NSString *)where;
- (NSArray *)queryByClass:(Class)cls order:(NSString *)order;
- (NSArray *)queryByClass:(Class)cls limit:(NSString *)limit;
- (NSArray *)queryByClass:(Class)cls where:(NSString *)where order:(NSString *)order;
- (NSArray *)queryByClass:(Class)cls order:(NSString *)order limit:(NSString *)limit;
- (NSArray *)queryByClass:(Class)cls where:(NSString *)where limit:(NSString *)limit;
/**
 查询数据

 @param cls 类型【对应的数据表】
 @param where 条件语句
 @param order 排序【已添加order关键字，只需要添加排序e.g: by name desc】
 @param limit 限定【已添加limit关键字，e.g: 100 [offset 15]->限制100条数据，从编码15开始】
 @return 数据列表
 */
- (NSArray *)queryByClass:(Class)cls where:(NSString *)where order:(NSString *)order limit:(NSString *)limit;

- (NSInteger)queryCountByClass:(Class)cls where:(NSString *)where;


/**
 更新数据

 @param model 数据模型【必须包含关键字：默认为_id】
 @return EKOSError
 */
- (EKOSError)updateModel:(id)model;
- (EKOSError)updateModel:(id)model where:(NSString *)where;


/**
 更新数据

 @param model 数据模型
 @param replaceNil 是否需要替换默认值【为nil的字段内容，会使用默认值覆盖掉】
 @return EKOSError
 */
- (EKOSError)updateModel:(id)model replaceNil:(BOOL)replaceNil;
- (EKOSError)updateModel:(id)model where:(NSString *)where replaceNil:(BOOL)replaceNil;

/**
 清空数据

 @param cls 数据模型
 @return 是否成功
 */
- (EKOSError)clearByClass:(Class)cls;

/**
 根据条件删除数据

 @param cls 数据模型
 @param where 条件语句
 @return 成功与否
 */
- (EKOSError)deleteByClass:(Class)cls where:(NSString *)where;

/**
 删除数据【根据自定义的主键删除】

 @param model 数据模型
 @return 成功
 */
- (EKOSError)deleteByModel:(id)model;


/**
 删除数据列表

 @param models 数据列表【数据格式需统一】
 @return 删除条数
 */
- (NSInteger)deleteByModels:(NSArray *)models;

/**
 移除数据库

 @param cls 数据模型
 @return 成功与否
 */
- (EKOSError)removeByClass:(Class)cls;
- (EKOSError)removeAll;

/**
 当前数据模型保存的版本号

 @param cls 数据模型类
 @return 版本号【默认版本号从1.0开始】
 */
- (NSString *)versionOfClass:(Class)cls;

//直接使用原始数据操作数据库
- (EKOSError)saveByValue:(NSDictionary *)values intoTable:(NSString *)tableName;
- (NSArray *)findfromTable:(NSString *)tableName;

@end
