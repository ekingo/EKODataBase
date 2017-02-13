更新记录

0.0.6
支持NSArray和NSDictionary嵌套写入（不再需要实现encodeWithCoder和initWithDecoder）；

0.0.5
支持过滤属性字段（添加黑名单）[eko_ignoreProperties]
支持是否包含父类属性（默认包含）

0.0.4
支持类表自动扩展字段（新的字段只能增加，不能删除或是修改类型）
支持更新数据时，是否替换Nil字段为默认值（insert插入数据时，过滤掉为nil字段的值）

0.0.3
支持在类中添加unionPrimaryKeys作为联合关键字【关键字定义类型只支持基本类型NSNumber，NSString】

0.0.2
支持NSArray：如果是自定义类，需要实现encodeWithCoder和initWithDecoder；(详见测试用例）

0.0.1
直接保存类到数据库中
支持类型：NSString、NSNumber、NSData；
支持类嵌套：类中再定义子类；
支持数据库加密处理：可按类定义不同的加密密钥；【需要添加FMDB/SQLCiper第三方库】
支持数据库按版本自动迁移；

说明
支持保存数据格式：
基础类型：int,float,double,char;
NSString;
NSNumber;
NSData;
NSError/NSValue/NSSet/NSDate: 自定义类需要实现encodeWithCoder/initWithDecoder;
NSArray;
NSDictionary;
/*

//数据模型:
1,+VERSION：数据库版本，不同的版本会对数据库进行自动升级；
2,+PASSWORD：单独设置数据库密码（此密码为最优先级，依次为Mgr设置的Class密码->通用密码）
3,_id：该字段为数据库内置关键字，readonly[自增]

@interface EDBTestModel : NSObject

@property (nonatomic, readonly) NSString *_id; //default primary key

+ (NSString *)VERSION;
+ (NSString *)PASSWORD; //该密码为最优先级

@end

@implementation EDBTestModel

+ (NSString *)VERSION{
return @"1.1";
}

+ (NSString *)PASSWORD{
return @"123456";
}

@end

另外定义类的+函数接口
+ (NSArray *)eko_unionPrimaryKeys{
//联合主键
}

+ (NSNumber *)eko_isContainsParentProperties{
//是否包含父类属性，默认包含，避免由于一些系统定义的类有过多属性需要查询
//1:包含；0：不包含
}

+ (NSArray *)eko_ignoreProperties{
//写入数据库时，不包含解析的属性字段
}

TODOList:
1，数据库保存一份（避免数据库频繁的打开关闭）；
2，insert的NSArray列表时，可以是多个数据表；

最初版本源代码来源于该项目：
https://github.com/netyouli/WHC_ModelSqliteKit
