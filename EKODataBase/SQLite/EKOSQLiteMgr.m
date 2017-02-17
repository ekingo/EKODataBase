//
//  EKOSQLiteMgr.m
//  EKODataBase
//
//  Created by kingo on 25/01/2017.
//  Copyright © 2017 XTC. All rights reserved.
//

#import "EKOSQLiteMgr.h"

#import <objc/runtime.h>
#import <objc/message.h>
#import <sqlite3.h>

#define  EDB_String    (@"TEXT")
#define  EDB_Int       (@"INTERGER")
#define  EDB_Boolean   (@"INTERGER")
#define  EDB_Double    (@"DOUBLE")
#define  EDB_Float     (@"DOUBLE")
#define  EDB_Char      (@"NVARCHAR")
#define  EDB_Model     (@"INTERGER")
#define  EDB_Data      (@"BLOB")

typedef NS_OPTIONS(NSInteger, EDB_FieldType) {
    _String     =      1 << 0,
    _Int        =      1 << 1,
    _Boolean    =      1 << 2,
    _Double     =      1 << 3,
    _Float      =      1 << 4,
    _Char       =      1 << 5,
    _Number     =      1 << 6,
    _Model      =      1 << 7,
    _Data       =      1 << 8,
    _Blob       =      1 << 9, //NSArray等转换成NSData以二进制的形式保存？
    _Array      =      1 << 10,
    _Dictionary =      1 << 11,
};

typedef NS_OPTIONS(NSInteger, EDB_QueryType) {
    _Where      =      1 << 0,
    _Order      =      1 << 1,
    _Limit      =      1 << 2,
    _WhereOrder =      1 << 3,
    _WhereLimit =      1 << 4,
    _OrderLimit =      1 << 5,
    _WhereOrderLimit = 1 << 6
};

@interface EDBPropertyInfo : NSObject

@property (nonatomic, assign, readonly) EDB_FieldType type;
@property (nonatomic, copy, readonly)   NSString * name;
@property (nonatomic, assign, readonly) SEL setter;
@property (nonatomic, assign, readonly) SEL getter;

@end

@implementation EDBPropertyInfo

- (instancetype)initWithType:(EDB_FieldType)type propertyName:(NSString *)property_name{
    self = [super init];
    if (self) {
        _name = property_name.mutableCopy;
        _type = type;
        if (property_name.length>0) {
            if (property_name.length>1) {
                _setter = NSSelectorFromString([NSString stringWithFormat:@"set%@%@:",[property_name substringToIndex:1].uppercaseString,[property_name substringFromIndex:1]]);
            }else{
                _setter = NSSelectorFromString([NSString stringWithFormat:@"set%@:",[property_name substringToIndex:1].uppercaseString]);
            }
            _getter = NSSelectorFromString(property_name);
        }
    }
    
    return self;
}

@end

#pragma mark - EKOSQLiteMgr
static sqlite3 *_edb_database;
static NSInteger kNoHandleKeyId = -2;

//默认所有类的加密密匙
NSString *const kEDBEncryptKeyNormalClass = @"EDBNormalClass";

//动态支持函数接口
NSString *const kDynamicFunctionVersion     = @"VERSION";
NSString *const kDynamicFunctionPassword    = @"PASSWORD";
NSString *const kDefaultPrimaryKey          = @"_id"; //默认主键字段
NSString *const kUnionPrimaryKeys           = @"eko_unionPrimaryKeys"; //联合主键
NSString *const kContainParentProperties    = @"eko_isContainsParentProperties"; //是否保存父类property，默认包含
NSString *const kIgnoreProperties           = @"eko_ignoreProperties"; //写入数据库时需要排除掉的关键字

#define kEDBKeyJsonModelName   @"eko_jsonModelName_key_ignore"

@interface EKOSQLiteMgr()

@property (nonatomic, strong) NSMutableDictionary * sub_model_info;
#if OS_OBJECT_HAVE_OBJC_SUPPORT
@property (nonatomic, strong) dispatch_semaphore_t dsema;
#else
@property (nonatomic, assign) dispatch_semaphore_t dsema;
#endif

//@property (nonatomic, strong) sqlite3 *
@property (nonatomic, copy) NSString *dbWorkSpace;

@property (nonatomic, strong) NSMutableDictionary *encryptKeys; //不同modelClass可能对应不同的加密方式

@end


@implementation EKOSQLiteMgr

- (instancetype)init{
    self = [super init];
    if (self) {
        self.sub_model_info = [NSMutableDictionary dictionary];
        self.dsema = dispatch_semaphore_create(1);
    }
    
    return self;
}

- (void)dealloc{
    if (_edb_database) {
        [self closeDatabase];
    }
}

#pragma mark - private methods

- (id)valueforModel:(id)model withProperyInfo:(EDBPropertyInfo *)propertyInfo{
    id value = [model valueForKey:propertyInfo.name];
    
    if(!value){
        switch (propertyInfo.type) {
            case _Array:
            case _Dictionary:{
            }
                break;
            case _Data: {
                
            }
                break;
            case _Blob:{
                
            }
                break;
            case _String: {
            }
                break;
            case _Number: {
            }
                break;
            case _Model: {
            }
                break;
            case _Int: {
                value = @(((int64_t (*)(id, SEL))(void *) objc_msgSend)((id)model, propertyInfo.getter));
            }
                break;
            case _Boolean: {
                value = @(((Boolean (*)(id, SEL))(void *) objc_msgSend)((id)model, propertyInfo.getter));
            }
                break;
            case _Char: {
                value = @(((int8_t (*)(id, SEL))(void *) objc_msgSend)((id)model, propertyInfo.getter));
            }
                break;
            case _Double: {
                value = @(((double (*)(id, SEL))(void *) objc_msgSend)((id)model, propertyInfo.getter));
            }
                break;
            case _Float: {
                value = @(((float (*)(id, SEL))(void *) objc_msgSend)((id)model, propertyInfo.getter));
            }
                break;
            default:
                break;
        }
    }
    
    return value;
}

#pragma mark - NSData/NSValue/... to/from NSData/NString
/**
 非基本类型的数据格式，转换成二进制之后再保存

 @param value NSArray或是NSDictionary等
 @param flag 编码或解码
 @return 二进制数据
 */
- (NSData *)archiveValue:(id)value encode:(BOOL)flag{
    NSData *data = nil;
    if (flag) {
        __block BOOL validate = YES;
        if ([value isKindOfClass:[NSArray class]]) {
            [value enumerateObjectsUsingBlock:^(id obj,NSUInteger idx,BOOL *stop){
                if (!([obj respondsToSelector:@selector(encodeWithCoder:)] && [obj respondsToSelector:@selector(initWithCoder:)])) {
                    NSLog(@"%@ must imp encodeWithCoder and initWithCoder!",obj);
                    validate = NO;
                    *stop = YES;
                }
            }];
        }
        
        if (validate) {
            data = [NSKeyedArchiver archivedDataWithRootObject:value];
        }else{
            NSLog(@"数据格式错误!(%@)",value);
        }
    }else{
        data = [NSKeyedUnarchiver unarchiveObjectWithData:value];
    }
    
    return data;
}

- (NSString *)encodeDataToString:(NSData *)data{
    if ([data isKindOfClass:[NSData class]]) {
        data = [data base64EncodedDataWithOptions:0];
        NSString *ret = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    
        return ret;
    }
    
    return nil;
}

- (NSData *)decodeFromString:(NSString *)str{
    if ([str isKindOfClass:[NSString class]]) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:str options:NSDataBase64DecodingIgnoreUnknownCharacters];
        return data;
    }else{
        return nil;
    }
}

#pragma mark - NSArray/NSDictionary to/from JsonData
- (id)toJsonDataFromModel:(id)model{
    id jsonObject = nil;
    if ([model isKindOfClass:[NSString class]] || [model isKindOfClass:[NSNumber class]]){
        jsonObject = model;
    }
    else if([model isKindOfClass:[NSArray class]]){
        jsonObject = [self toJsonDataFromArray:model];
    }else if([model isKindOfClass:[NSDictionary class]]){
        jsonObject = [self toJsonDataFromDictionary:model];
    }else if([self isSupportClass:[model class]]){
        jsonObject = [self archiveValue:model encode:YES]; //NSData
    }else{
        if([NSJSONSerialization isValidJSONObject:model]){
            NSError *error = nil;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:model
                                                               options:0
                                                                 error:&error];
            
            if ([jsonData length] > 0 && error == nil){
                return jsonData;
            }else{
                return nil;
            }
        }else{
            NSLog(@"格式错误！无法使用转存json保存");
        }
        //jsonObject = [self jsonObjectWithModel:model];
    }
    
    return jsonObject;
}

- (id)toJsonDataFromArray:(NSArray *)array{
    NSError *error = nil;
    if([NSJSONSerialization isValidJSONObject:array]){
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:array
                                                           options:0
                                                             error:&error];
        
        if ([jsonData length] > 0 && error == nil){
            return jsonData;
        }else{
            return nil;
        }
    }else{
        NSMutableArray* toArray = [NSMutableArray array];
        NSInteger count = array.count;
        for (NSInteger i = 0; i < count; i++){
            id obj = [array objectAtIndex:i];
            id jsonObject = [self jsonObjectWithModel:obj];
            if(jsonObject){
                [toArray addObject:jsonObject];
            }
        }
        
        if(toArray.count){
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:toArray
                                                               options:0
                                                                 error:&error];
            
            if ([jsonData length] > 0 && error == nil){
                return jsonData;
            }else{
                return nil;
            }
        }
    }
    return nil;
}

- (id)toJsonDataFromDictionary:(NSDictionary *)dict{
    if([NSJSONSerialization isValidJSONObject:dict]){
        NSError *error = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict
                                                           options:0
                                                             error:&error];
        
        if ([jsonData length] > 0 && error == nil){
            return jsonData;
        }else{
            return nil;
        }
    }
    else
    {
        NSMutableDictionary* toDic = [NSMutableDictionary dictionary];
        NSArray* allKeys = dict.allKeys;
        for (NSInteger i = 0; i<allKeys.count; i++)
        {
            NSString* key = [allKeys objectAtIndex:i];
            id obj = [dict objectForKey:key];
            id jsonObject = [self jsonObjectWithModel:obj];
            if(jsonObject)
            {
                [toDic setObject:jsonObject forKey:key];
            }
        }
        
        if(toDic.count)
        {
            NSError *error = nil;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:toDic
                                                               options:0
                                                                 error:&error];
            
            if ([jsonData length] > 0 && error == nil){
                return jsonData;
            }else{
                return nil;
            }
        }
    }
    return nil;
}

//模型转成字典类型，使其可以进行保存
- (id)jsonObjectWithArray:(NSArray *)array{
    if (array) {
        NSMutableArray *results = [NSMutableArray array];
        for (id obj in array) {
            id jsonObject = [self jsonObjectWithModel:obj];
            if (jsonObject) {
                [results addObject:jsonObject];
            }
        }
        
        return results;
    }
    
    return nil;
}
- (id)jsonObjectWithDictionary:(NSDictionary *)dict{
    if (dict) {
        NSMutableDictionary *results = [NSMutableDictionary dictionary];
        for (NSString *key in dict.allKeys) {
            id obj = [dict valueForKey:key];
            id jsonObject = [self jsonObjectWithModel:obj];
            
            if (jsonObject) {
                [results setValue:jsonObject forKey:key];
            }
        }
        
        return results;
    }
    
    return nil;
}

- (id)jsonObjectWithModel:(id)model{
    if ([model isKindOfClass:[NSArray class]]) {
        return [self jsonObjectWithArray:model];
    }else if([model isKindOfClass:[NSDictionary class]]){
        return [self jsonObjectWithDictionary:model];
    }else if([self isSupportClass:[model class]]){
        return model;
    }
    
    NSDictionary *fields = [self parserModelObjectFieldsWithModelClass:[model class]];
    //转换成字典可保存的数据
    if ([fields count] > 0) {
        NSMutableDictionary *results = [NSMutableDictionary dictionary];
        for (NSString *field in fields.allKeys) {
            EDBPropertyInfo *propertyInfo = fields[field];
            
            id value = [self valueforModel:model withProperyInfo:propertyInfo];
            if (value) {
                switch (propertyInfo.type) {
                    case _Array:
                    case _Dictionary:{
                        if ([value isKindOfClass:[NSArray class]]) {
                            value = [self jsonObjectWithArray:value];
                        }else if([value isKindOfClass:[NSDictionary class]]){
                            value = [self jsonObjectWithDictionary:value];
                        }else{
                            NSLog(@"value=%@ is invalid",value);
                        }
                    }
                        break;
                    case _Model:{
                        value = [self jsonObjectWithModel:value];
                    }
                        break;
                    case _Data:{
                        value = [self encodeDataToString:value];
                    }
                        break;
                    case _Blob:{
                        //二进制数据需要转换之后才可以用
                        value = [self archiveValue:value encode:YES];
                        if (value) {
                            value = [self encodeDataToString:value];
                        }
                    }
                        break;
                    default:
                        break;
                }
            }
            if (value) {
                [results setValue:value forKey:field];
            }
        }
        
        if ([results count]>0) {
            [results setValue:NSStringFromClass([model class]) forKey:kEDBKeyJsonModelName];
        }
        
        return results;
    }
    
    return nil;
}

- (id)modelFromJsonValue:(id)jsonValue{
    NSError *error = nil;
    id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonValue
                                                    options:NSJSONReadingAllowFragments
                                                      error:&error];
    
    if (jsonObject != nil && error == nil){
        if ([jsonObject isKindOfClass:[NSArray class]]) {
            return [self modelFromArray:jsonObject];
        }else if([jsonObject isKindOfClass:[NSDictionary class]]){
            return [self modelFromDictionary:jsonObject];
        }
        return jsonObject;
    }else{
        // 解析错误
        return nil;
    }
}

- (id)modelFromArray:(NSArray *)array{
    NSMutableArray *results = [NSMutableArray array];
    for (id model in array) {
        id result = nil;
        if ([model isKindOfClass:[NSArray class]]) {
            result = [self modelFromArray:model];
        }else{
            if([model isKindOfClass:[NSDictionary class]]){
                id value = [model valueForKey:kEDBKeyJsonModelName];
                if (value) {
                    //这是转换之后的dict
                    result = [self modelWithJsonModel:model];
                }else{
                    result = [self modelFromDictionary:model];
                }
            }else{
                result = [self modelWithJsonModel:model];
            }
        }
        
        if (result) {
            [results addObject:result];
        }
    }
    return results;
}

- (id)modelFromDictionary:(NSDictionary *)dic{
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    for (NSString *key in dic.allKeys) {
        id model = [dic objectForKey:key];
        id result = nil;
        
        if ([model isKindOfClass:[NSArray class]]) {
            result = [self modelFromArray:model];
        }else {
            if([model isKindOfClass:[NSDictionary class]]){
                id value = [model valueForKey:kEDBKeyJsonModelName];
                if (value) {
                    result = [self modelWithJsonModel:model];
                }else{
                    result = [self modelFromDictionary:model];
                }
            }else{
                result = [self modelWithJsonModel:model];
            }
        }
        
        if (result) {
            [results setObject:result forKey:key];
        }
    }
    
    return results;
}

- (id)modelWithJsonModel:(id)jsonModel{
    if ([jsonModel isKindOfClass:[NSDictionary class]]) {
        NSString *clsName = [jsonModel valueForKey:kEDBKeyJsonModelName];
        if (!clsName) {
            NSLog(@"未设置ModelName");
            return nil;
        }
        
        Class cls = NSClassFromString(clsName);
        id model = [[cls alloc] init];
        
        NSDictionary *fields = [self parserModelObjectFieldsWithModelClass:NSClassFromString(clsName)];
        //转换成字典可保存的数据
        if ([fields count] > 0) {
            for (NSString *field in fields.allKeys) {
                EDBPropertyInfo *propertyInfo = fields[field];
                id value = [jsonModel valueForKey:field];
                if (!value) {
                    continue;
                }
                
                switch (propertyInfo.type) {
                    case _Array:
                    case _Dictionary:{
                        if ([value isKindOfClass:[NSArray class]]) {
                            value = [self modelFromArray:value];
                        }else if([value isKindOfClass:[NSDictionary class]]){
                            value = [self modelFromDictionary:value];
                        }else{
                            NSLog(@"理论上不会存在这样的类型了，因为需要外面最上层做处理=%@",value);
                        }
                        if (value) {
                            [model setValue:value forKey:field];
                        }
                    }
                        break;
                    case _Blob:{
                        //首先需要进行解码
                        id encoder = [self decodeFromString:value];
                        
                        id unarchive = [self archiveValue:encoder encode:NO];
                        if (unarchive) {
                            [model setValue:unarchive forKey:field];
                        }else{
                            NSLog(@"field=%@ decode failed",field);
                        }
                    }
                        break;
                    case _Number:
                    case _String:
                        [model setValue:value forKey:field];
                        break;
                    case _Data:{
                        id encoder = [self decodeFromString:value];
                        if (encoder) {
                            [model setValue:encoder forKey:field];
                        }
                    }
                        break;
                    case _Model:{
                        value = [self modelWithJsonModel:value];
                        if (value) {
                            [model setValue:value forKey:field];
                        }
                    }
                        break;
                    case _Int: {
                        if ([value isKindOfClass:[NSNumber class]]) {
                            int iValue = [value intValue];
                            ((void (*)(id, SEL, int64_t))(void *) objc_msgSend)((id)model, propertyInfo.setter, iValue);
                        }
                    }
                        break;
                    case _Float: {
                        if ([value isKindOfClass:[NSNumber class]]) {
                            float iValue = [value floatValue];
                            ((void (*)(id, SEL, float))(void *) objc_msgSend)((id)model, propertyInfo.setter, iValue);
                        }
                    }
                        break;
                    case _Double: {
                        if ([value isKindOfClass:[NSNumber class]]) {
                            float iValue = [value floatValue];
                            ((void (*)(id, SEL, double))(void *) objc_msgSend)((id)model, propertyInfo.setter, iValue);
                        }
                    }
                        break;
                    case _Char: {
                        if ([value isKindOfClass:[NSNumber class]]) {
                            int iValue = [value intValue];
                            ((void (*)(id, SEL, int))(void *) objc_msgSend)((id)model, propertyInfo.setter, iValue);
                        }
                    }
                        break;
                    case _Boolean: {
                        if ([value isKindOfClass:[NSNumber class]]) {
                            int iValue = [value intValue];
                            ((void (*)(id, SEL, int))(void *) objc_msgSend)((id)model, propertyInfo.setter, iValue);
                        }
                    }
                        break;
                        
                    default:
                        break;
                }
            }
            
            return model;
        }
        
        return nil;
    }else{
        NSLog(@"直接使用返回的value:（%@）",jsonModel);
        return jsonModel;
    }
}

#pragma mark - dynamic funcs
- (id)performFunc:(NSString *)func forClass:(Class)cls{
    SEL selFunc = NSSelectorFromString(func);
    id result = nil;
    if ([cls respondsToSelector:selFunc]) {
        IMP imp_func = [cls methodForSelector:selFunc];
        NSString * (*func)(id, SEL) = (void *)imp_func;
        result = func(cls, selFunc);
    }
    
    return result;
}

- (id)performFunc:(NSString *)func forModel:(id)model{
    SEL selFunc = NSSelectorFromString(func);
    id result = nil;
    if ([model respondsToSelector:selFunc]) {
        //result = [model performSelector:selFunc];
        IMP imp_func = [model methodForSelector:selFunc];
        NSString * (*func)(id, SEL) = (void *)imp_func;
        result = func(model, selFunc);
    }
    
    return result;
}

- (NSString *)primaryKeyWhereSQLForModel:(id)model{
    NSMutableString *sql = [NSMutableString stringWithString:@""];
    
    NSArray *primaryKeys = [self performFunc:kUnionPrimaryKeys forClass:[model class]];
    if ([primaryKeys count]>0) {
        NSMutableDictionary *where = [NSMutableDictionary dictionary];
        for (NSString *key in primaryKeys) {
            id value = [model valueForKey:key];
            if (value) {
                [where setValue:value forKey:key];
            }
        }
        
        sql = [self genSQLWithWhere:where];
    }
    
    return sql;
}

//model可以生产的where语句
#pragma mark - sql
- (NSString *)allPrimaryKeyWhereSQLForModel:(id)model{
    NSString *where = nil;
    
    do {
        NSString *_id = [self performFunc:kDefaultPrimaryKey forModel:model];
        if (_id) {
            where = [NSString stringWithFormat:@"%@=%@",kDefaultPrimaryKey,_id];
            break;
        }
    
        where = [self primaryKeyWhereSQLForModel:model];
        if (where.length>0) {
            break;
        }
        
    }while(0);
    
    return where;
}

- (NSString *)genSQLWithWhere:(id)where{
    NSMutableString *sql = [NSMutableString stringWithString:@""];
    if ([where isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)where;
        for (NSString *key in dict.allKeys) {
            id value = [dict valueForKey:key];
            if (sql.length>0) {
                [sql appendString:@" and "];
            }
            
            if ([value isKindOfClass:[NSNumber class]]) {
                [sql appendString:[NSString stringWithFormat:@"%@=%@",key,value]];
            }else{
                [sql appendString:[NSString stringWithFormat:@"%@=\'%@\'",key,value]];
            }
        }
    }else if([where isKindOfClass:[NSString class]]){
        sql = where;
    }else{
        NSLog(@"where=%@语句有错误！",where);
    }
    
    return sql;
}

- (NSDictionary *)removePrimaryKeyFields:(NSDictionary *)fields forModel:(id)model{
    NSMutableDictionary *results = [NSMutableDictionary dictionaryWithDictionary:fields];
    NSArray *primaryKeys = [self performFunc:kUnionPrimaryKeys forClass:[model class]];
    for (NSString *key in primaryKeys) {
        [results removeObjectForKey:key];
    }
    
    return results;
}

- (NSString *)databaseCacheDirectory {
    if (_dbWorkSpace) {
        return self.dbWorkSpace;
    }
    
    return [NSString stringWithFormat:@"%@/Library/Caches/EKODataBase/",NSHomeDirectory()];
}

- (NSString *)commonLocalPathWithClass:(Class)model_class isPath:(BOOL)isPath {
    NSString * class_name = NSStringFromClass(model_class);
    NSFileManager * file_manager = [NSFileManager defaultManager];
    NSString * file_directory = [self databaseCacheDirectory];
    BOOL isDirectory = YES;
    __block NSString * file_path = nil;
    if ([file_manager fileExistsAtPath:file_directory isDirectory:&isDirectory]) {
        NSArray <NSString *> * file_name_array = [file_manager contentsOfDirectoryAtPath:file_directory error:nil];
        if (file_name_array != nil && file_name_array.count > 0) {
            [file_name_array enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                if ([obj rangeOfString:class_name].location != NSNotFound) {
                    if (isPath) {
                        file_path = [NSString stringWithFormat:@"%@%@",file_directory,obj];
                    }else {
                        file_path = [obj mutableCopy];
                    }
                    *stop = YES;
                }
            }];
        }
    }
    return file_path;
}

- (NSString *)localNameWithClass:(Class)cls {
    return [self commonLocalPathWithClass:cls isPath:NO];
}

- (NSString *)localPathWithClass:(Class)cls {
    return [self commonLocalPathWithClass:cls isPath:YES];
}

- (EDB_FieldType)parserFieldTypeWithAttr:(NSString *)attr {
    NSArray * sub_attrs = [attr componentsSeparatedByString:@","];
    NSString * first_sub_attr = sub_attrs.firstObject;
    first_sub_attr = [first_sub_attr substringFromIndex:1];
    EDB_FieldType field_type = _String;
    const char type = *[first_sub_attr UTF8String];
    switch (type) {
        case 'B':
            field_type = _Boolean;
            break;
        case 'c':
        case 'C':
            field_type = _Char;
            break;
        case 's':
        case 'S':
        case 'i':
        case 'I':
        case 'l':
        case 'L':
        case 'q':
        case 'Q':
            field_type = _Int;
            break;
        case 'f':
            field_type = _Float;
            break;
        case 'd':
        case 'D':
            field_type = _Double;
            break;
        default:
            break;
    }
    return field_type;
}

- (NSString *)databaseFieldTypeWithType:(EDB_FieldType)type {
    switch (type) {
        case _String:
            return EDB_String;
        case _Model:
            return EDB_Model;
        case _Int:
            return EDB_Int;
        case _Number:
            return EDB_Double;
        case _Double:
            return EDB_Double;
        case _Float:
            return EDB_Float;
        case _Char:
            return EDB_Char;
        case _Boolean:
            return EDB_Boolean;
        case _Data:
            return EDB_Data;
        case _Blob:
            return EDB_Data;
        case _Array:
            return EDB_Data;
        case _Dictionary:
            return EDB_Data;
        default:
            break;
    }
    return EDB_String;
}

- (NSDictionary *)parserModelObjectFieldsWithModelClass:(Class)modelClass{
    if (modelClass == [NSObject class]) {
        //如果是NSObject，则意味着还没有定义字段
        return nil;
    }
    
    NSArray *ignores = [self performFunc:kIgnoreProperties forClass:modelClass];
    
    NSMutableDictionary * fields = [NSMutableDictionary dictionary];
    unsigned int property_count = 0;
    objc_property_t * propertys = class_copyPropertyList(modelClass, &property_count);
    for (int i = 0; i < property_count; i++) {
        objc_property_t property = propertys[i];
        const char * property_name = property_getName(property);
        const char * property_attributes = property_getAttributes(property);
        NSString * property_name_string = [NSString stringWithUTF8String:property_name];
        
        if ([ignores containsObject:property_name_string]) {
            NSLog(@"ignore property:%@",property_name_string);
            continue;
        }
        
        NSString * property_attributes_string = [NSString stringWithUTF8String:property_attributes];
        NSArray * property_attributes_list = [property_attributes_string componentsSeparatedByString:@"\""];
        if (property_attributes_list.count == 1) {
            // base type
            EDB_FieldType type = [self parserFieldTypeWithAttr:property_attributes_list[0]];
            EDBPropertyInfo * property_info = [[EDBPropertyInfo alloc] initWithType:type propertyName:property_name_string];
            [fields setObject:property_info forKey:property_name_string];
        }else {
            // refernece type
            Class class_type = NSClassFromString([self parsePropertyName:property_attributes_list[1]]);
            if (class_type == [NSNumber class]) {
                EDBPropertyInfo * property_info = [[EDBPropertyInfo alloc] initWithType:_Number propertyName:property_name_string];
                [fields setObject:property_info forKey:property_name_string];
            }else if (class_type == [NSString class]) {
                EDBPropertyInfo * property_info = [[EDBPropertyInfo alloc] initWithType:_String propertyName:property_name_string];
                [fields setObject:property_info forKey:property_name_string];
            }else if (class_type == [NSData class]) {
                EDBPropertyInfo * property_info = [[EDBPropertyInfo alloc] initWithType:_Data propertyName:property_name_string];
                [fields setObject:property_info forKey:property_name_string];
            }else if(class_type == [NSArray class]){
                EDBPropertyInfo * property_info = [[EDBPropertyInfo alloc] initWithType:_Array propertyName:property_name_string];
                [fields setObject:property_info forKey:property_name_string];
            }else if(class_type == [NSDictionary class]){
                EDBPropertyInfo * property_info = [[EDBPropertyInfo alloc] initWithType:_Dictionary propertyName:property_name_string];
                [fields setObject:property_info forKey:property_name_string];
            }else if ([self isSupportClass:class_type]) {
                NSLog(@"检查模型类异常数据类型(不支持类型：%@)[自定义类型需要实现encodeWithCoder/initWithCoder",class_type);
                EDBPropertyInfo * property_info = [[EDBPropertyInfo alloc] initWithType:_Blob propertyName:property_name_string];
                [fields setObject:property_info forKey:property_name_string];
            }else {
                EDBPropertyInfo * property_info = [[EDBPropertyInfo alloc] initWithType:_Model propertyName:property_name_string];
                [fields setObject:property_info forKey:property_name_string];
            }
        }
    }
    free(propertys);
    
    if (modelClass.superclass) {
        id containsParent = [self performFunc:kContainParentProperties forClass:modelClass];
        BOOL bIncludeParent = YES; //默认包含父类定义的属性
        if (containsParent && [containsParent respondsToSelector:@selector(boolValue)]) {
            bIncludeParent = [containsParent boolValue];
        }
        
        if (bIncludeParent) {
            NSDictionary *fieldSuper = [self parserModelObjectFieldsWithModelClass:modelClass.superclass];
            [fieldSuper enumerateKeysAndObjectsUsingBlock:^(id key,id obj,BOOL *stop){
                [fields setValue:obj forKey:key];
            }];
        }
    }
    
    return fields;
}

- (NSDictionary *)parseFieldsWithValues:(NSDictionary *)keyvalues{
    NSMutableDictionary * fields = [NSMutableDictionary dictionary];
    NSArray *keys = [keyvalues allKeys];
    for (NSString *key in keys) {
        id value = [keyvalues valueForKey:key];
        if ([value isKindOfClass:[NSNumber class]]) {
            EDBPropertyInfo * property_info = [[EDBPropertyInfo alloc] initWithType:_Number propertyName:key];
            [fields setObject:property_info forKey:key];
        }else if([value isKindOfClass:[NSString class]]){
            EDBPropertyInfo * property_info = [[EDBPropertyInfo alloc] initWithType:_String propertyName:key];
            [fields setObject:property_info forKey:key];
        }else if([value isKindOfClass:[NSData class]]){
            EDBPropertyInfo * property_info = [[EDBPropertyInfo alloc] initWithType:_Data propertyName:key];
            [fields setObject:property_info forKey:key];
        }else if([value isKindOfClass:[NSArray class]]){
            EDBPropertyInfo * property_info = [[EDBPropertyInfo alloc] initWithType:_Array propertyName:key];
            [fields setObject:property_info forKey:key];
        }else if([value isKindOfClass:[NSDictionary class]]){
            EDBPropertyInfo * property_info = [[EDBPropertyInfo alloc] initWithType:_Dictionary propertyName:key];
            [fields setObject:property_info forKey:key];
        }else if([self isSupportClass:[value class]]){
            NSLog(@"type %@ not supported!",[value class]);
            EDBPropertyInfo * property_info = [[EDBPropertyInfo alloc] initWithType:_Blob propertyName:key];
            [fields setObject:property_info forKey:key];
        }else{
            EDBPropertyInfo * property_info = [[EDBPropertyInfo alloc] initWithType:_Model propertyName:key];
            [fields setObject:property_info forKey:key];
        }
    }
    
    return fields;
}

- (NSDictionary *)scanCommonSubModel:(id)model isClass:(BOOL)isClass {
    Class model_class = isClass ? model : [model class];
    NSMutableDictionary * sub_model_info = [NSMutableDictionary dictionary];
    unsigned int property_count = 0;
    objc_property_t * propertys = class_copyPropertyList(model_class, &property_count);
    
    NSArray *ignores = [self performFunc:kIgnoreProperties forClass:model_class];
    
    for (int i = 0; i < property_count; i++) {
        objc_property_t property = propertys[i];
        const char * property_name = property_getName(property);
        const char * property_attributes = property_getAttributes(property);
        NSString * property_name_string = [NSString stringWithUTF8String:property_name];
        
        if ([ignores containsObject:property_name_string]) {
            continue;
        }
        
        NSString * property_attributes_string = [NSString stringWithUTF8String:property_attributes];
        NSArray * property_attributes_list = [property_attributes_string componentsSeparatedByString:@"\""];
        if (property_attributes_list.count > 1) {
            Class class_type = NSClassFromString([self parsePropertyName:property_attributes_list[1]]);
            if (![self isSupportClass:class_type]) {
                //不是基本支持的类型，则是二级子目录
                //TODO：非自定义的类需要做ignore
                if (isClass) {
                    [sub_model_info setObject:[self parsePropertyName:property_attributes_list[1]] forKey:property_name_string];
                }else {
                    id sub_model = [model valueForKey:property_name_string];
                    if (sub_model) {
                        [sub_model_info setObject:sub_model forKey:property_name_string];
                    }
                }
            }
        }
    }
    free(propertys);
    return sub_model_info;
}

- (NSDictionary * )scanSubModelClass:(Class)cls {
    return [self scanCommonSubModel:cls isClass:YES];
}

- (NSDictionary * )scanSubModelObject:(id)model_object {
    return [self scanCommonSubModel:model_object isClass:NO];
}

#pragma mark - sqlite
- (sqlite_int64)getModelMaxIdWithClass:(Class)model_class {
    sqlite_int64 max_id = 0;
    if (_edb_database) {
        NSString * select_sql = [NSString stringWithFormat:@"SELECT MAX(_id) AS MAXVALUE FROM %@",NSStringFromClass(model_class)];
        sqlite3_stmt * pp_stmt = nil;
        if (sqlite3_prepare_v2(_edb_database, [select_sql UTF8String], -1, &pp_stmt, nil) == SQLITE_OK) {
            while (sqlite3_step(pp_stmt) == SQLITE_ROW) {
                max_id = sqlite3_column_int64(pp_stmt, 0);
            }
        }
        sqlite3_finalize(pp_stmt);
    }
    return max_id;
}

- (NSArray *)getModelFieldNameWithClass:(Class)model_class {
    NSMutableArray * field_name_array = [NSMutableArray array];
    if (_edb_database) {
        NSString * select_sql = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE _id = %lld",NSStringFromClass(model_class),[self getModelMaxIdWithClass:model_class]];
        sqlite3_stmt * pp_stmt = nil;
        if (sqlite3_prepare_v2(_edb_database, [select_sql UTF8String], -1, &pp_stmt, nil) == SQLITE_OK) {
            int colum_count = sqlite3_column_count(pp_stmt);
            for (int column = 1; column < colum_count; column++) {
                NSString * field_name = [NSString stringWithCString:sqlite3_column_name(pp_stmt, column) encoding:NSUTF8StringEncoding];
                [field_name_array addObject:field_name];
            }
        }
        sqlite3_finalize(pp_stmt);
    }
    return field_name_array;
}

#pragma mark - table
//数据表是否存在
- (BOOL)isTableExists:(NSString *)tableName{
    
    BOOL bRes = NO;
    do {
        if (!tableName || [tableName length]<=0) {
            bRes = NO;
            break;
        }
        
        NSString *sql = [NSString stringWithFormat:@"SELECT COUNT(*) FROM sqlite_master where type='table' and name='%@';",tableName];
        sqlite3_stmt *statement;
        
        if( sqlite3_prepare_v2(_edb_database, [sql UTF8String], -1, &statement, NULL) == SQLITE_OK ){
            //Loop through all the returned rows (should be just one)
            int count = 0;
            while( sqlite3_step(statement) == SQLITE_ROW ){
                count = sqlite3_column_int(statement, 0);
            }
            if (count>0) {
                bRes = YES;
            }
            sqlite3_finalize(statement);
        }else{
            NSLog( @"Failed from sqlite3_prepare_v2. Error is:  %s", sqlite3_errmsg(_edb_database));
        }
    }while(0);
    
    return bRes;
}

- (void)updateTableFieldWithModel:(Class)model_class newVersion:(NSString *)newVersion localModelName:(NSString *)local_model_name {
    @autoreleasepool {
        NSString * table_name = NSStringFromClass(model_class);
        NSString * cache_directory = [self databaseCacheDirectory];
        NSString * database_cache_path = [NSString stringWithFormat:@"%@%@",cache_directory,local_model_name];
        
        //文件存在时，才需要进行迁移
        if (![[NSFileManager defaultManager] fileExistsAtPath:database_cache_path]) {
            return;
        }
        
        if ([self openDataBase:database_cache_path encryptKey:[self encryptKeyForClass:model_class]] == EKOSErrorNone) {
            NSArray * old_model_field_name_array = [self getModelFieldNameWithClass:model_class];
            NSDictionary * new_model_info = [self parserModelObjectFieldsWithModelClass:model_class];
            NSMutableString * delete_field_names = [NSMutableString string];
            NSMutableString * add_field_names = [NSMutableString string];
            [old_model_field_name_array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                if (new_model_info[obj] == nil) {
                    [delete_field_names appendString:obj];
                    [delete_field_names appendString:@" ,"];
                }
            }];
            [new_model_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, EDBPropertyInfo * obj, BOOL * _Nonnull stop) {
                if (![old_model_field_name_array containsObject:key]) {
                    [add_field_names appendFormat:@"%@ %@,",key,[self databaseFieldTypeWithType:obj.type]];
                }
            }];
            if (add_field_names.length > 0) {
                NSArray * add_field_name_array = [add_field_names componentsSeparatedByString:@","];
                [add_field_name_array enumerateObjectsUsingBlock:^(NSString * obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    if (obj.length > 0) {
                        NSString * add_field_name_sql = [NSString stringWithFormat:@"ALTER TABLE %@ ADD %@",table_name,obj];
                        [self execSql:add_field_name_sql];
                    }
                }];
            }
            if (delete_field_names.length > 0) {
                [delete_field_names deleteCharactersInRange:NSMakeRange(delete_field_names.length - 1, 1)];
                NSString * select_sql = [NSString stringWithFormat:@"SELECT * FROM %@",table_name];
                NSMutableArray * old_model_data_array = [NSMutableArray array];
                sqlite3_stmt * pp_stmt = nil;
                NSDictionary * sub_model_class_info = [self scanSubModelClass:model_class];
                NSMutableString * sub_model_name = [NSMutableString string];
                [sub_model_class_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
                    [sub_model_name appendString:key];
                    [sub_model_name appendString:@" "];
                }];
                if (sqlite3_prepare_v2(_edb_database, [select_sql UTF8String], -1, &pp_stmt, nil) == SQLITE_OK) {
                    int colum_count = sqlite3_column_count(pp_stmt);
                    while (sqlite3_step(pp_stmt) == SQLITE_ROW) {
                        id new_model_object = [model_class new];
                        for (int column = 1; column < colum_count; column++) {
                            NSString * old_field_name = [NSString stringWithCString:sqlite3_column_name(pp_stmt, column) encoding:NSUTF8StringEncoding];
                            EDBPropertyInfo * property_info = new_model_info[old_field_name];
                            if (property_info == nil) continue;
                            switch (property_info.type) {
                                case _Number: {
                                    double value = sqlite3_column_double(pp_stmt, column);
                                    [new_model_object setValue:@(value) forKey:old_field_name];
                                }
                                    break;
                                case _Model: {
                                    sqlite3_int64 value = sqlite3_column_int64(pp_stmt, column);
                                    [new_model_object setValue:@(value) forKey:old_field_name];
                                }
                                    break;
                                case _Int: {
                                    sqlite3_int64 value = sqlite3_column_int64(pp_stmt, column);
                                    if (sub_model_name != nil && sub_model_name.length > 0) {
                                        if ([sub_model_name rangeOfString:old_field_name].location == NSNotFound) {
                                            ((void (*)(id, SEL, int64_t))(void *) objc_msgSend)((id)new_model_object, property_info.setter, value);
                                        }else {
                                            [new_model_object setValue:@(value) forKey:old_field_name];
                                        }
                                    }else {
                                        ((void (*)(id, SEL, int64_t))(void *) objc_msgSend)((id)new_model_object, property_info.setter, value);
                                    }
                                }
                                    break;
                                case _String: {
                                    const unsigned char * text = sqlite3_column_text(pp_stmt, column);
                                    if (text != NULL) {
                                        NSString * value = [NSString stringWithCString:(const char *)text encoding:NSUTF8StringEncoding];
                                        [new_model_object setValue:value forKey:old_field_name];
                                    }else {
                                        [new_model_object setValue:@"" forKey:old_field_name];
                                    }
                                }
                                    break;
                                case _Data: {
                                    int length = sqlite3_column_bytes(pp_stmt, column);
                                    const void * blob = sqlite3_column_blob(pp_stmt, column);
                                    if (blob) {
                                        NSData * value = [NSData dataWithBytes:blob length:length];
                                        [new_model_object setValue:value forKey:old_field_name];
                                    }else {
                                        [new_model_object setValue:[NSData data] forKey:old_field_name];
                                    }
                                }
                                    break;
                                case _Array:
                                case _Dictionary:{
                                    int length = sqlite3_column_bytes(pp_stmt, column);
                                    const void * blob = sqlite3_column_blob(pp_stmt, column);
                                    if (blob) {
                                        NSData * value = [NSData dataWithBytes:blob length:length];
                                        id jsonModel = [self modelFromJsonValue:value];
                                        
                                        [new_model_object setValue:jsonModel forKey:old_field_name];
                                    }else {
                                        [new_model_object setValue:[NSData data] forKey:old_field_name];
                                    }
                                }
                                    break;
                                case _Blob:{
                                    int length = sqlite3_column_bytes(pp_stmt, column);
                                    const void * blob = sqlite3_column_blob(pp_stmt, column);
                                    if (blob) {
                                        NSData * value = [NSData dataWithBytes:blob length:length];
                                        NSData *data = [self archiveValue:value encode:NO];
                                        
                                        [new_model_object setValue:data forKey:old_field_name];
                                    }else {
                                        [new_model_object setValue:[NSData data] forKey:old_field_name];
                                    }
                                }
                                    break;
                                case _Char:
                                case _Boolean: {
                                    int value = sqlite3_column_int(pp_stmt, column);
                                    ((void (*)(id, SEL, int))(void *) objc_msgSend)((id)new_model_object, property_info.setter, value);
                                }
                                    break;
                                case _Float:
                                case _Double: {
                                    double value = sqlite3_column_double(pp_stmt, column);
                                    ((void (*)(id, SEL, float))(void *) objc_msgSend)((id)new_model_object, property_info.setter, value);
                                }
                                    break;
                                default:
                                    break;
                            }
                        }
                        [old_model_data_array addObject:new_model_object];
                    }
                }
                sqlite3_finalize(pp_stmt);
                [self closeDatabase];
                
                NSFileManager * file_manager = [NSFileManager defaultManager];
                NSString * file_path = [self localPathWithClass:model_class];
                if (file_path) {
                    [file_manager removeItemAtPath:file_path error:nil];
                }
                
                if ([self openTable:model_class]) {
                    [self execSql:@"BEGIN"];
                    [old_model_data_array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                        [self commonInsert:obj index:kNoHandleKeyId];
                    }];
                    [self execSql:@"COMMIT"];
                    [self closeDatabase];
                    return;
                }
            }
            [self closeDatabase];
            NSString * new_database_cache_path = [NSString stringWithFormat:@"%@%@_v%@.sdb",cache_directory,table_name,newVersion];
            NSFileManager * file_manager = [NSFileManager defaultManager];
            [file_manager moveItemAtPath:database_cache_path toPath:new_database_cache_path error:nil];
        }
    }
}

- (NSString *)tablePathForClass:(Class)cls autoCreate:(BOOL)autoCreate{
    NSFileManager * file_manager = [NSFileManager defaultManager];
    NSString * cache_directory = [self databaseCacheDirectory];
    BOOL is_directory = YES;
    if (![file_manager fileExistsAtPath:cache_directory isDirectory:&is_directory]) {
        if (autoCreate) {
            [file_manager createDirectoryAtPath:cache_directory withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
    
    NSString * version = [self performFunc:kDynamicFunctionVersion forClass:cls];
    if (version) {
        NSString * local_model_name = [self localNameWithClass:cls];
        if (local_model_name != nil &&
            [local_model_name rangeOfString:version].location == NSNotFound) {
            [self updateTableFieldWithModel:cls
                                 newVersion:version
                             localModelName:local_model_name];
        }
    }else{
        version = @"1.0";
    }
    
    NSString * database_cache_path = [NSString stringWithFormat:@"%@%@_v%@.sdb",cache_directory,NSStringFromClass(cls),version];
    
    return database_cache_path;
}

- (BOOL)openTable:(Class)model_class {
    if (!model_class || model_class == [NSNull class]) {
        return NO;
    }
    
    //密码
    NSString *password = [self performFunc:kDynamicFunctionPassword forClass:model_class];
    if (!password) {
        password = [self encryptKeyForClass:model_class];
    }
    
    NSString * database_cache_path = [self tablePathForClass:model_class autoCreate:YES];
    //if (sqlite3_open([database_cache_path UTF8String], &_edb_database) == SQLITE_OK) {
    if([self openDataBase:database_cache_path encryptKey:password] == EKOSErrorNone){
        return [self createTable:model_class];
    }
    return NO;
}

/**
更新数据表字段

 @param tableName 表名
 @param fields 新的数据字段
 @return 结果
 */
- (BOOL)alterTable:(NSString *)tableName fields:(NSDictionary *)fields{
    BOOL bRes = YES;
    
    NSArray *columNames = [self commonQueryAllColumnNames:tableName lowerCase:1];
    
    for (NSString * field in fields) {
        EDBPropertyInfo * property_info = fields[field];
        if ([columNames containsObject:[property_info.name lowercaseString]]) {
            continue;
        }
        
        NSMutableString *sql = [NSMutableString string];
        
        [sql appendFormat:@"%@ %@ ",field, [self databaseFieldTypeWithType:property_info.type]];
        switch (property_info.type) {
            case _Blob:
            case _Data:
            case _String:
            case _Char:
            case _Array:
            case _Dictionary:
                [sql appendString:@"DEFAULT NULL"];
                break;
            case _Boolean:
            case _Int:
            case _Model:
                [sql appendString:@"DEFAULT 0"];
                break;
            case _Float:
            case _Double:
            case _Number:
                [sql appendString:@"DEFAULT 0.0"];
                break;
            default:
                break;
        }
        
        if (sql.length>0) {
            [sql insertString:[NSString stringWithFormat:@"alter table %@ add column ",tableName] atIndex:0];
            
            bRes = [self execSql:sql];
        }
        
        if (!bRes) {
            break;
        }
    }
    
    //primary keys

    return bRes;
}

- (BOOL)createTable:(NSString *)tableName fields:(NSDictionary *)fields primaryKeys:(NSArray *)primaryKeys{
    BOOL bRes = NO;
    
    if (fields[kDefaultPrimaryKey]) {
        //插入时，过滤掉默认主键
        NSMutableDictionary *temp = [NSMutableDictionary dictionaryWithDictionary:fields];
        [temp removeObjectForKey:kDefaultPrimaryKey];
        fields = temp;
    }
    
    do {
        if (fields.count <= 0) {
            break;
        }
        
        //首先判断数据表是否已存在，是否需要更新字段
        if ([self isTableExists:tableName]) {
            //更新字段
            NSLog(@"table:%@ has existed",tableName);
            
            bRes = [self alterTable:tableName fields:fields];
            break;
        }
        
        NSString * create_table_sql = nil;
        if ([primaryKeys count]>0) {
            create_table_sql = [NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (_id INTEGER,",tableName];
        }else{
            create_table_sql = [NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (_id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,",tableName];
        }
        NSArray * field_array = fields.allKeys;
        for (NSString * field in field_array) {
            EDBPropertyInfo * property_info = fields[field];
            create_table_sql = [create_table_sql stringByAppendingFormat:@"%@ %@ DEFAULT ",field, [self databaseFieldTypeWithType:property_info.type]];
            switch (property_info.type) {
                case _Blob:
                case _Data:
                case _String:
                case _Char:
                case _Array:
                case _Dictionary:
                    create_table_sql = [create_table_sql stringByAppendingString:@"NULL,"];
                    break;
                case _Boolean:
                case _Int:
                case _Model:
                    create_table_sql = [create_table_sql stringByAppendingString:@"0,"];
                    break;
                case _Float:
                case _Double:
                case _Number:
                    create_table_sql = [create_table_sql stringByAppendingString:@"0.0,"];
                    break;
                default:
                    break;
            }
        }
        create_table_sql = [create_table_sql substringWithRange:NSMakeRange(0, create_table_sql.length - 1)];
        
        //primary keys
        if ([primaryKeys count]>0) {
            NSMutableString *pkstr = [NSMutableString stringWithString:@""];
            for (NSString *pk in primaryKeys) {
                if (pkstr.length >0 ) {
                    [pkstr appendString:@","];
                }
                [pkstr appendString:pk];
            }
            if ([pkstr length]>0) {
                [pkstr insertString:@",primary key(_id," atIndex:0];
                [pkstr appendString:@")"];
                create_table_sql = [create_table_sql stringByAppendingString:pkstr];
            }
        }
        
        create_table_sql = [create_table_sql stringByAppendingString:@")"];
        bRes = [self execSql:create_table_sql];
    }while(0);
    
    return bRes;
}

- (BOOL)createTable:(Class)modelClass {
    NSString * table_name = NSStringFromClass(modelClass);
    NSDictionary * field_dictionary = [self parserModelObjectFieldsWithModelClass:modelClass];
    NSArray *pks = [self performFunc:kUnionPrimaryKeys forClass:modelClass];
    
    return [self createTable:table_name fields:field_dictionary primaryKeys:pks];
}

- (BOOL)execSql:(NSString *)sql {
    char *error;
    BOOL bRes = sqlite3_exec(_edb_database, [sql UTF8String], nil, nil, &error);
    
    if (bRes != SQLITE_OK) {
        printf("error:%s",error);
    }
    
    return bRes == SQLITE_OK;
}

- (NSDictionary *)indexByColumnName:(sqlite3_stmt *)init_statement {
    NSMutableArray *keys = [[NSMutableArray alloc] init];
    NSMutableArray *values = [[NSMutableArray alloc] init];
    int num_fields = sqlite3_column_count(init_statement);
    for(int index_value = 0; index_value < num_fields; index_value++) {
        const char* field_name = sqlite3_column_name(init_statement, index_value);
        if (!field_name){
            field_name="";
        }
        NSString *col_name = [NSString stringWithUTF8String:field_name];
        NSNumber *index_num = [NSNumber numberWithInt:index_value];
        [keys addObject:col_name];
        [values addObject:index_num];
    }
    NSDictionary *dictionary = [NSDictionary dictionaryWithObjects:values forKeys:keys];
    return dictionary;
}

- (NSArray *)findBySql:(NSString *)sql{
    
    NSMutableArray *result = [[NSMutableArray alloc] init];
    const char *sqlStatement = (const char*)[sql UTF8String];
    sqlite3_stmt *compiledStatement;
    if(sqlite3_prepare_v2(_edb_database, sqlStatement, -1, &compiledStatement, NULL) == SQLITE_OK) {
        NSDictionary *dictionary = [self indexByColumnName:compiledStatement];
        while(sqlite3_step(compiledStatement) == SQLITE_ROW) {
            NSMutableDictionary * row = [[NSMutableDictionary alloc] init];
            for (NSString *field in dictionary) {
                char * str = (char *)sqlite3_column_text(compiledStatement, [[dictionary objectForKey:field] intValue]);
                if (!str){
                    str=" ";
                }
                NSString * value = [NSString stringWithUTF8String:str];
                [row setObject:value forKey:field];
            }
            [result addObject:row];
        }
    }
    else {
        NSAssert1(0, @"Error sqlite3_prepare_v2 :. '%s'", sqlite3_errmsg(_edb_database));
    }
    sqlite3_finalize(compiledStatement);
    
    return result;
}

#pragma mark - insert
- (int)commonInsert:(id)model_object index:(NSInteger)index {
    int iRes = SQLITE_OK;
    
    do {
        sqlite3_stmt * pp_stmt = nil;
        NSDictionary * field_dictionary = [self parserModelObjectFieldsWithModelClass:[model_object class]];
        //primary key
    //    NSString *_id = [self performFunc:kDefaultPrimaryKey forModel:model_object];
    //    if (_id) {
    //        iRes = [self updateCommonModel:model_object where:[NSString stringWithFormat:@"%@=%@",kDefaultPrimaryKey,_id]];
    //        
    //        if (iRes == SQLITE_OK) {
    //            return iRes;
    //        }
    //    }
        
        //有联合主键时，需要判断主键是否是更新数据
        NSString *primaryKeyWhere = [self primaryKeyWhereSQLForModel:model_object];
        if ([primaryKeyWhere length]>0) {
            
            int iCount = [self commonQueryCountForModelClass:[model_object class] where:primaryKeyWhere];
            if (iCount > 0) {
                iRes = [self commonUpdateModel:model_object where:primaryKeyWhere subModelName:nil replaceNil:NO];
            
                if (iRes == SQLITE_OK) {
                    break;
                }
            }
        }
        
        if (field_dictionary[kDefaultPrimaryKey]) {
            //插入时，过滤掉默认主键
            NSMutableDictionary *temp = [NSMutableDictionary dictionaryWithDictionary:field_dictionary];
            [temp removeObjectForKey:kDefaultPrimaryKey];
            field_dictionary = temp;
        }
        
        NSString * table_name = NSStringFromClass([model_object class]);
        __block NSString * insert_sql = [NSString stringWithFormat:@"INSERT INTO %@ (",table_name];
        NSArray * field_array = field_dictionary.allKeys;
        NSMutableArray * value_array = [NSMutableArray array];
        NSMutableArray * insert_field_array = [NSMutableArray array];
        
        //[field_array enumerateObjectsUsingBlock:^(NSString *  _Nonnull field, NSUInteger idx, BOOL * _Nonnull stop) {
        for (NSString *field in field_array) {
            id value = [model_object valueForKey:field];
            EDBPropertyInfo * property_info = field_dictionary[field];
            
            if (!value && property_info.type != _Model) {
                //值为空时，不做更改
                continue;
            }
            
            [insert_field_array addObject:field];
            insert_sql = [insert_sql stringByAppendingFormat:@"%@,",field];
            
            id subModelKeyId = self.sub_model_info[property_info.name];
            if ((value && subModelKeyId == nil) || index == kNoHandleKeyId) {
                [value_array addObject:value];
            }else {
                switch (property_info.type) {
                    case _Array:
                    case _Dictionary:
                    case _Blob:
                    case _Data: {
                        [value_array addObject:[NSData data]];
                    }
                        break;
                    case _String: {
                        [value_array addObject:@""];
                    }
                        break;
                    case _Number: {
                        [value_array addObject:@(0.0)];
                    }
                        break;
                    case _Model: {
                        if ([subModelKeyId isKindOfClass:[NSArray class]]) {
                            [value_array addObject:subModelKeyId[index]];
                        }else {
                            if (subModelKeyId) {
                                [value_array addObject:subModelKeyId];
                            }else {
                                [value_array addObject:@(kNoHandleKeyId)];
                            }
                        }
                    }
                        break;
                    case _Int: {
                        id sub_model_main_key_object = self.sub_model_info[property_info.name];
                        if (sub_model_main_key_object != nil) {
                            if (index != -1) {
                                [value_array addObject:sub_model_main_key_object[index]];
                            }else {
                                [value_array addObject:sub_model_main_key_object];
                            }
                        }else {
                            NSNumber * value = @(((int64_t (*)(id, SEL))(void *) objc_msgSend)((id)model_object, property_info.getter));
                            [value_array addObject:value];
                        }
                    }
                        break;
                    case _Boolean: {
                        NSNumber * value = @(((Boolean (*)(id, SEL))(void *) objc_msgSend)((id)model_object, property_info.getter));
                        [value_array addObject:value];
                    }
                        break;
                    case _Char: {
                        NSNumber * value = @(((int8_t (*)(id, SEL))(void *) objc_msgSend)((id)model_object, property_info.getter));
                        [value_array addObject:value];
                    }
                        break;
                    case _Double: {
                        NSNumber * value = @(((double (*)(id, SEL))(void *) objc_msgSend)((id)model_object, property_info.getter));
                        [value_array addObject:value];
                    }
                        break;
                    case _Float: {
                        NSNumber * value = @(((float (*)(id, SEL))(void *) objc_msgSend)((id)model_object, property_info.getter));
                        [value_array addObject:value];
                    }
                        break;
                    default:
                        break;
                }
            }
        }
        
        if ([insert_field_array count] <=0) {
            NSLog(@"没有数据需要插入，不做处理！");
            break;
        }
        
        insert_sql = [insert_sql substringWithRange:NSMakeRange(0, insert_sql.length - 1)];
        insert_sql = [insert_sql stringByAppendingString:@") VALUES ("];
        
        [insert_field_array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            insert_sql = [insert_sql stringByAppendingString:@"?,"];
        }];
        insert_sql = [insert_sql substringWithRange:NSMakeRange(0, insert_sql.length - 1)];
        insert_sql = [insert_sql stringByAppendingString:@")"];
        
        iRes = sqlite3_prepare_v2(_edb_database, [insert_sql UTF8String], -1, &pp_stmt, nil);
        if (iRes == SQLITE_OK) {
            [insert_field_array enumerateObjectsUsingBlock:^(NSString *  _Nonnull field, NSUInteger idx, BOOL * _Nonnull stop) {
                EDBPropertyInfo * property_info = field_dictionary[field];
                id value = value_array[idx];
                int index = (int)[insert_field_array indexOfObject:field] + 1;
                switch (property_info.type) {
                    case _Data:
                        sqlite3_bind_blob(pp_stmt, index, [value bytes], (int)[value length], SQLITE_TRANSIENT);
                        break;
                    case _Array:
                    case _Dictionary:{
                        NSLog(@"value:%@",value);
                        NSData *data = [self toJsonDataFromModel:value];
                        if (data) {
                            sqlite3_bind_blob(pp_stmt, index, [data bytes], (int)[data length], SQLITE_TRANSIENT);
                        }else{
                            NSLog(@"数据格式错误，无法保存数据：%@",value);
                        }
                    }
                        break;
                    case _Blob:{
                        NSLog(@"value:%@",value);
                        //使用二进制保存数据
                        NSData *data = [self archiveValue:value encode:YES];
                        if (data) {
                            sqlite3_bind_blob(pp_stmt, index, [data bytes], (int)[data length], SQLITE_TRANSIENT);
                        }else{
                            NSLog(@"数据格式错误，无法保存数据：%@",value);
                        }
                    }
                        break;
                    case _String:
                        if (![value isKindOfClass:[NSString class]]) {
                            if ([value respondsToSelector:@selector(stringValue)]) {
                                value = [value stringValue];
                            }else{
                                NSLog(@"value:%@ is not NSString!!!",value);
                                break;
                            }
                        }
                        sqlite3_bind_text(pp_stmt, index, [value UTF8String], -1, SQLITE_TRANSIENT);
                        break;
                    case _Number:
                        sqlite3_bind_double(pp_stmt, index, [value doubleValue]);
                        break;
                    case _Model:
                        sqlite3_bind_int64(pp_stmt, index, (sqlite3_int64)[value integerValue]);
                        break;
                    case _Int:
                        sqlite3_bind_int64(pp_stmt, index, (sqlite3_int64)[value longLongValue]);
                        break;
                    case _Boolean: //BOOL类型使用int保存
                        sqlite3_bind_int(pp_stmt, index, [value intValue]);
                        break;
                    case _Char:
                        sqlite3_bind_int(pp_stmt, index, [value intValue]);
                        break;
                    case _Float:
                        sqlite3_bind_double(pp_stmt, index, [value floatValue]);
                        break;
                    case _Double:
                        sqlite3_bind_double(pp_stmt, index, [value doubleValue]);
                        break;
                    default:
                        break;
                }
            }];
            
            if (sqlite3_step(pp_stmt) != SQLITE_DONE) {
                iRes = sqlite3_finalize(pp_stmt);
            }
        }else {
            NSLog(@"Sorry存储数据失败,建议检查模型类属性类型是否符合规范(sql=%@)",insert_sql);
        }
        
    }while(0);
    
    return iRes;
}

- (NSArray *)commonInsertSubArrayModelObject:(NSArray *)sub_array_model_object {
    NSMutableArray * id_array = [NSMutableArray array];
    __block sqlite_int64 _id = -1;
    Class first_sub_model_class = [sub_array_model_object.firstObject class];
    if (sub_array_model_object.count > 0 &&
        [self openTable:first_sub_model_class]) {
        _id = [self getModelMaxIdWithClass:first_sub_model_class];
        [self execSql:@"BEGIN"];
        [sub_array_model_object enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            _id++;
            [self commonInsert:obj index:idx];
            [id_array addObject:@(_id)];
        }];
        [self execSql:@"COMMIT"];
        [self closeDatabase];
    }
    return id_array;
}

- (NSArray *)inserSubModelArray:(NSArray *)model_array {
    id first_model_object = model_array.firstObject;
    NSDictionary * sub_model_object_info = [self scanSubModelObject:first_model_object];
    if (sub_model_object_info.count > 0) {
        NSMutableDictionary * sub_model_object_info = [NSMutableDictionary dictionary];
        [model_array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary * temp_sub_model_object_info = [self scanSubModelObject:obj];
            [temp_sub_model_object_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
                if (sub_model_object_info[key] != nil) {
                    NSMutableArray * temp_sub_array = [sub_model_object_info[key] mutableCopy];
                    [temp_sub_array addObject:obj];
                    sub_model_object_info[key] = temp_sub_array;
                }else {
                    NSMutableArray * temp_sub_array = [NSMutableArray array];
                    [temp_sub_array addObject:obj];
                    sub_model_object_info[key] = temp_sub_array;
                }
            }];
        }];
        if (sub_model_object_info.count > 0) {
            [sub_model_object_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, NSArray * subArray, BOOL * _Nonnull stop) {
                NSArray * sub_id_array = [self inserSubModelArray:subArray];
                self.sub_model_info[key] = sub_id_array;
            }];
        }
    }
    return [self commonInsertSubArrayModelObject:model_array];
}

- (sqlite_int64)commonInsertSubModelObject:(id)sub_model_object {
    sqlite_int64 _id = -1;
    if ([self openTable:[sub_model_object class]]) {
        [self execSql:@"BEGIN"];
        int iRes = [self commonInsert:sub_model_object index:-1];
        [self execSql:@"COMMIT"];
        if (iRes == SQLITE_OK) {
            _id = [self getModelMaxIdWithClass:[sub_model_object class]];
        }
        [self closeDatabase];
    }
    return _id;
}

- (sqlite_int64)commonInsertSubModel:(id)subModel forModel:(id)model where:(NSString *)where subField:(NSString *)field_name{
    sqlite_int64 idx = [self commonInsertSubModelObject:subModel];
    if (idx > 0) {
        NSString *_idSub = [self performFunc:kDefaultPrimaryKey forModel:subModel];
        if (!_idSub) {
            _idSub = [NSString stringWithFormat:@"%ld",(long)idx];
        }
        
        if ([self openTable:[model class]]) {
            NSString *sql = [NSString stringWithFormat:@"update %@ set %@=%@",[model class],field_name,_idSub];
            if (where && where.length>0) {
                sql = [sql stringByAppendingString:[NSString stringWithFormat:@" where %@",where]];
            }
            [self execSql:sql];
            
            [self closeDatabase];
        }
    }
    
    return idx;
}

- (sqlite_int64)insertModelObject:(id)model_object {
    NSDictionary * sub_model_objects_info = [self scanSubModelObject:model_object];
    if (sub_model_objects_info.count > 0) {
        [sub_model_objects_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            sqlite_int64 _id = [self insertModelObject:obj];
            [self.sub_model_info setObject:@(_id) forKey:key];
        }];
    }
    return [self commonInsertSubModelObject:model_object];
}

#pragma mark - query
- (NSArray *)commonQuery:(Class)model_class conditions:(NSArray *)conditions subModelName:(NSString *)sub_model_name queryType:(EDB_QueryType)query_type {
    
    if (![self openTable:model_class]) return @[];
    
    NSDictionary * field_dictionary = [self parserModelObjectFieldsWithModelClass:model_class];
    NSString * table_name = NSStringFromClass(model_class);
    NSString * select_sql = [NSString stringWithFormat:@"SELECT * FROM %@",table_name];
    NSString * where = nil;
    NSString * order = nil;
    NSString * limit = nil;
    if (conditions != nil && conditions.count > 0) {
        switch (query_type) {
            case _Where: {
                where = conditions.firstObject;
                if (where.length > 0) {
                    select_sql = [select_sql stringByAppendingFormat:@" WHERE %@",where];
                }
            }
                break;
            case _Order: {
                order = conditions.firstObject;
                if (order.length > 0) {
                    select_sql = [select_sql stringByAppendingFormat:@" ORDER %@",order];
                }
            }
                break;
            case _Limit:
                limit = conditions.firstObject;
                if (limit.length > 0) {
                    select_sql = [select_sql stringByAppendingFormat:@" LIMIT %@",limit];
                }
                break;
            case _WhereOrder: {
                if (conditions.count > 0) {
                    where = conditions.firstObject;
                    if (where.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" WHERE %@",where];
                    }
                }
                if (conditions.count > 1) {
                    order = conditions.lastObject;
                    if (order.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" ORDER %@",order];
                    }
                }
            }
                break;
            case _WhereLimit: {
                if (conditions.count > 0) {
                    where = conditions.firstObject;
                    if (where.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" WHERE %@",where];
                    }
                }
                if (conditions.count > 1) {
                    limit = conditions.lastObject;
                    if (limit.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" LIMIT %@",limit];
                    }
                }
            }
                break;
            case _OrderLimit: {
                if (conditions.count > 0) {
                    order = conditions.firstObject;
                    if (order.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" ORDER %@",order];
                    }
                }
                if (conditions.count > 1) {
                    limit = conditions.lastObject;
                    if (limit.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" LIMIT %@",limit];
                    }
                }
            }
                break;
            case _WhereOrderLimit: {
                if (conditions.count > 0) {
                    where = conditions.firstObject;
                    if (where.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" WHERE %@",where];
                    }
                }
                if (conditions.count > 1) {
                    order = conditions[1];
                    if (order.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" ORDER %@",order];
                    }
                }
                if (conditions.count > 2) {
                    limit = conditions.lastObject;
                    if (limit.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" LIMIT %@",limit];
                    }
                }
            }
                break;
            default:
                break;
        }
    }
    NSMutableArray * model_object_array = [NSMutableArray array];
    sqlite3_stmt * pp_stmt = nil;
    if (sqlite3_prepare_v2(_edb_database, [select_sql UTF8String], -1, &pp_stmt, nil) == SQLITE_OK) {
        int colum_count = sqlite3_column_count(pp_stmt);
        while (sqlite3_step(pp_stmt) == SQLITE_ROW) {
            id model_object = [model_class new];
            for (int column = 0; column < colum_count; column++) {//column 包含自动添加的主键_id，方便update
                NSString * field_name = [NSString stringWithCString:sqlite3_column_name(pp_stmt, column) encoding:NSUTF8StringEncoding];
                EDBPropertyInfo * property_info = field_dictionary[field_name];
                if (property_info == nil) continue;
                switch (property_info.type) {
                    case _Data: {
                        int length = sqlite3_column_bytes(pp_stmt, column);
                        const void * blob = sqlite3_column_blob(pp_stmt, column);
                        if (blob != NULL) {
                            NSData * value = [NSData dataWithBytes:blob length:length];
                            [model_object setValue:value forKey:field_name];
                        }
                    }
                        break;
                    case _Array:
                    case _Dictionary:{
                        int length = sqlite3_column_bytes(pp_stmt, column);
                        const void * blob = sqlite3_column_blob(pp_stmt, column);
                        if (blob != NULL) {
                            NSData * value = [NSData dataWithBytes:blob length:length];
                            id jsonObjct = [self modelFromJsonValue:value];
                            
                            [model_object setValue:jsonObjct forKey:field_name];
                        }
                    }
                        break;
                    case _Blob:{
                        int length = sqlite3_column_bytes(pp_stmt, column);
                        const void * blob = sqlite3_column_blob(pp_stmt, column);
                        if (blob != NULL) {
                            NSData * value = [NSData dataWithBytes:blob length:length];
                            NSData *data = [self archiveValue:value encode:NO];
                            
                            [model_object setValue:data forKey:field_name];
                        }
                    }
                        break;
                    case _String: {
                        const unsigned char * text = sqlite3_column_text(pp_stmt, column);
                        if (text != NULL) {
                            NSString * value = [NSString stringWithCString:(const char *)text encoding:NSUTF8StringEncoding];
                            [model_object setValue:value forKey:field_name];
                        }
                    }
                        break;
                    case _Number: {
                        double value = sqlite3_column_double(pp_stmt, column);
                        [model_object setValue:@(value) forKey:field_name];
                    }
                        break;
                    case _Model: {
                        sqlite3_int64 value = sqlite3_column_int64(pp_stmt, column);
                        [model_object setValue:@(value) forKey:field_name];
                    }
                        break;
                    case _Int: {
                        sqlite3_int64 value = sqlite3_column_int64(pp_stmt, column);
                        if (sub_model_name != nil && sub_model_name.length > 0) {
                            if ([sub_model_name rangeOfString:field_name].location == NSNotFound) {
                                ((void (*)(id, SEL, int64_t))(void *) objc_msgSend)((id)model_object, property_info.setter, value);
                            }else {
                                [model_object setValue:@(value) forKey:field_name];
                            }
                        }else {
                            ((void (*)(id, SEL, int64_t))(void *) objc_msgSend)((id)model_object, property_info.setter, value);
                        }
                    }
                        break;
                    case _Float: {
                        double value = sqlite3_column_double(pp_stmt, column);
                        ((void (*)(id, SEL, float))(void *) objc_msgSend)((id)model_object, property_info.setter, value);
                    }
                        break;
                    case _Double: {
                        double value = sqlite3_column_double(pp_stmt, column);
                        ((void (*)(id, SEL, double))(void *) objc_msgSend)((id)model_object, property_info.setter, value);
                    }
                        break;
                    case _Char: {
                        int value = sqlite3_column_int(pp_stmt, column);
                        ((void (*)(id, SEL, int))(void *) objc_msgSend)((id)model_object, property_info.setter, value);
                    }
                        break;
                    case _Boolean: {
                        int value = sqlite3_column_int(pp_stmt, column);
                        ((void (*)(id, SEL, int))(void *) objc_msgSend)((id)model_object, property_info.setter, value);
                    }
                        break;
                    default:
                        break;
                }
            }
            [model_object_array addObject:model_object];
        }
    }else {
        NSLog(@"Sorry查询语句异常,建议检查查询条件Sql语句语法是否正确");
    }
    sqlite3_finalize(pp_stmt);
    [self closeDatabase];
    
    return model_object_array;
}

- (id)querySubModel:(Class)model_class conditions:(NSArray *)conditions queryType:(EDB_QueryType)query_type {
    NSDictionary * sub_model_class_info = [self scanSubModelClass:model_class];
    NSMutableString * sub_model_name = [NSMutableString new];
    [sub_model_class_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        [sub_model_name appendString:key];
        [sub_model_name appendString:@" "];
    }];
    if (sub_model_name.length > 0) {
        [sub_model_name deleteCharactersInRange:NSMakeRange(sub_model_name.length - 1, 1)];
    }
    NSArray * model_array = [self commonQuery:model_class conditions:conditions subModelName:sub_model_name queryType:query_type];
    NSObject * model = nil;
    if (model_array.count > 0) {
        model = model_array.lastObject;
    }
    if (model != nil) {
        [sub_model_class_info enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSString * obj, BOOL * _Nonnull stop) {
            Class sub_model_class = NSClassFromString(obj);
            id sub_model = [self querySubModel:sub_model_class conditions:@[[NSString stringWithFormat:@"_id = %d",[[model valueForKey:name] intValue]]] queryType:_Where];
            [model setValue:sub_model forKey:name];
        }];
    }
    return model;
}

- (NSArray *)queryModel:(Class)model_class conditions:(NSArray *)conditions queryType:(EDB_QueryType)query_type {
    
    if (!model_class) {
        return nil;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:[self tablePathForClass:model_class autoCreate:NO]]) {
        return nil;
    }
    
    dispatch_semaphore_wait(self.dsema, DISPATCH_TIME_FOREVER);
    [self.sub_model_info removeAllObjects];
    NSDictionary * sub_model_class_info = [self scanSubModelClass:model_class];
    NSMutableString * sub_model_name = [NSMutableString new];
    [sub_model_class_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        [sub_model_name appendString:key];
        [sub_model_name appendString:@" "];
    }];
    if (sub_model_name.length > 0) {
        [sub_model_name deleteCharactersInRange:NSMakeRange(sub_model_name.length - 1, 1)];
    }
    NSArray * model_array = [self commonQuery:model_class conditions:conditions subModelName:sub_model_name queryType:query_type];
    [model_array enumerateObjectsUsingBlock:^(NSObject * model, NSUInteger idx, BOOL * _Nonnull stop) {
        [sub_model_class_info enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSString * obj, BOOL * _Nonnull stop) {
            Class sub_model_class = NSClassFromString(obj);
            id sub_model = [self querySubModel:sub_model_class conditions:@[[NSString stringWithFormat:@"_id = %d",[[model valueForKey:name] intValue]]] queryType:_Where];
            [model setValue:sub_model forKey:name];
        }];
    }];
    dispatch_semaphore_signal(self.dsema);
    return model_array;
}

- (int)commonQueryCountForModelClass:(Class)cls where:(NSString *)where{
    int count = 0;
    
    NSString * table_name = NSStringFromClass(cls);
    NSString * select_sql = [NSString stringWithFormat:@"SELECT COUNT(*) FROM %@",table_name];
    if (where != nil && where.length > 0) {
        select_sql = [select_sql stringByAppendingFormat:@" WHERE %@",where];
    }
    
    sqlite3_stmt *statement;
    
    if( sqlite3_prepare_v2(_edb_database, [select_sql UTF8String], -1, &statement, NULL) == SQLITE_OK ){
        //Loop through all the returned rows (should be just one)
        while( sqlite3_step(statement) == SQLITE_ROW ){
            count = sqlite3_column_int(statement, 0);
        }
    }else{
        NSLog( @"Failed from sqlite3_prepare_v2. Error is:  %s", sqlite3_errmsg(_edb_database));
    }
    
    return count;
}


/**
 获取表中所有字段名称

 @param tableName 表名
 @param lowerCase 1：小写；2：大写
 @return 列表
 */
- (NSArray *)commonQueryAllColumnNames:(NSString *)tableName lowerCase:(NSInteger)lowerCase{
    //NSString *sql = [NSString stringWithFormat:@"select * from %@ limit 0;",tableName];
    NSString *sql = [NSString stringWithFormat:@"pragma table_info ('%@')",tableName];
    NSMutableArray *results = [NSMutableArray array];
    sqlite3_stmt *stmt;
    if( sqlite3_prepare_v2(_edb_database, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK ){
        while(sqlite3_step(stmt) == SQLITE_ROW){
            int cols = sqlite3_column_count(stmt);
            if (cols>1) {
                NSString *name = [NSString stringWithFormat:@"%s", sqlite3_column_text(stmt, 1)];
                if (lowerCase == 1) {
                    name = [name lowercaseString];
                }else if(lowerCase == 2){
                    name = [name uppercaseString];
                }
                [results addObject:name];
            }
        }
        
        sqlite3_finalize(stmt);
    }
    
    return results;
}

#pragma mark - update
- (int)commonUpdateModel:(id)model where:(NSString *)where subModelName:(NSString *)sub_model_name replaceNil:(BOOL)replaceNil{
    if (model == nil) return SQLITE_EMPTY;
    int iRes = SQLITE_OK;
    
    sqlite3_stmt * pp_stmt = nil;
    NSDictionary * field_dictionary = [self parserModelObjectFieldsWithModelClass:[model class]];
    
    //移除需要更新的关键字
    field_dictionary = [self removePrimaryKeyFields:field_dictionary forModel:model];
    
    NSString * table_name = NSStringFromClass([model class]);
    __block NSString * update_sql = [NSString stringWithFormat:@"UPDATE %@ SET ",table_name];
    
    NSArray * field_array = field_dictionary.allKeys;
    NSMutableArray * update_field_array = [NSMutableArray array];
    [field_array enumerateObjectsUsingBlock:^(id  _Nonnull field, NSUInteger idx, BOOL * _Nonnull stop) {
        EDBPropertyInfo * property_info = field_dictionary[field];
        if (!replaceNil) {
            //如果不需要替换nil字段值，则无需更新该字段内容
            id value = [model valueForKey:field];
            if (value) {
                if (property_info.type != _Model) {
                    update_sql = [update_sql stringByAppendingFormat:@"%@ = ?,",field];
                    [update_field_array addObject:field];
                }
            }
        }else{
            if (property_info.type != _Model) {
                update_sql = [update_sql stringByAppendingFormat:@"%@ = ?,",field];
                [update_field_array addObject:field];
            }
        }
    }];
    
    if ([update_field_array count]<=0) {
        NSLog(@"Update %@ empty",model);
        return iRes;
    }
    
    update_sql = [update_sql substringWithRange:NSMakeRange(0, update_sql.length - 1)];
    if (where != nil && where.length > 0) {
        update_sql = [update_sql stringByAppendingFormat:@" WHERE %@", where];
    }
    
    if (sqlite3_prepare_v2(_edb_database, [update_sql UTF8String], -1, &pp_stmt, nil) == SQLITE_OK) {
        __block int iResult = SQLITE_OK;
        
        [update_field_array enumerateObjectsUsingBlock:^(id  _Nonnull field, NSUInteger idx, BOOL * _Nonnull stop) {
            EDBPropertyInfo * property_info = field_dictionary[field];
            int index = (int)[update_field_array indexOfObject:field] + 1;
            switch (property_info.type) {
                case _Data: {
                    NSData * value = [model valueForKey:field];
                    if (value == nil) {
                        value = [NSData data];
                    }
                    iResult = sqlite3_bind_blob(pp_stmt, index, [value bytes], (int)[value length], SQLITE_TRANSIENT);
                }
                    break;
                case _String: {
                    id value = [model valueForKey:field];
                    if (value == nil) {
                        value = @"";
                    }
                    if (![value isKindOfClass:[NSString class]]) {
                        if ([value respondsToSelector:@selector(stringValue)]) {
                            value = [value stringValue];
                        }else{
                            NSLog(@"value:%@ is not NSString!!!(save value as empty string)",value);
                            break;
                        }
                    }
                    iResult = sqlite3_bind_text(pp_stmt, index, [value UTF8String], -1, SQLITE_TRANSIENT);
                }
                    break;
                case _Array:
                case _Dictionary:{
                    id value = [model valueForKey:field];
                    
                    NSData *data = [self toJsonDataFromModel:value];
                    if (data) {
                        iResult = sqlite3_bind_blob(pp_stmt, index, [data bytes], (int)[data length], SQLITE_TRANSIENT);
                    }else{
                        NSLog(@"数据格式错误，无法保存数据：%@",value);
                    }
                }
                    break;
                case _Blob:{
                    id value = [model valueForKey:field];
                    
                    NSData *data = [self archiveValue:value encode:YES];
                    if (data) {
                        iResult = sqlite3_bind_blob(pp_stmt, index, [data bytes], (int)[data length], SQLITE_TRANSIENT);
                    }else{
                        NSLog(@"数据格式错误，无法保存数据：%@",value);
                    }
                }
                    break;
                case _Number: {
                    NSNumber * value = [model valueForKey:field];
                    if (value == nil) {
                        value = @(0.0);
                    }
                    if (property_info.type != _Model) {
                        iResult = sqlite3_bind_double(pp_stmt, index, [value doubleValue]);
                    }
                }
                    break;
                case _Int: {
                    if (sub_model_name &&
                        [sub_model_name rangeOfString:field].location != NSNotFound){} else {
                        /* 32bit os type issue
                         long value = ((long (*)(id, SEL))(void *) objc_msgSend)((id)sub_model_object, property_info.getter);*/
                        NSNumber * value = [model valueForKey:field];
                        iResult = sqlite3_bind_int64(pp_stmt, index, (sqlite3_int64)[value longLongValue]);
                    }
                }
                    break;
                case _Char: {
                    char value = ((char (*)(id, SEL))(void *) objc_msgSend)((id)model, property_info.getter);
                    iResult =sqlite3_bind_int(pp_stmt, index, value);
                }
                    break;
                case _Float: {
                    float value = ((float (*)(id, SEL))(void *) objc_msgSend)((id)model, property_info.getter);
                    iResult = sqlite3_bind_double(pp_stmt, index, value);
                }
                    break;
                case _Double: {
                    double value = ((double (*)(id, SEL))(void *) objc_msgSend)((id)model, property_info.getter);
                    iResult = sqlite3_bind_double(pp_stmt, index, value);
                }
                    break;
                case _Boolean: {
                    BOOL value = ((BOOL (*)(id, SEL))(void *) objc_msgSend)((id)model, property_info.getter);
                    iResult = sqlite3_bind_int(pp_stmt, index, value);
                }
                    break;
                default:
                    break;
            }
            if (iResult != SQLITE_OK) {
                NSLog(@"Update Fail(res=%ld",(long)iResult);
                *stop = YES;
            }
        }];
        
        iRes = iResult;
        
        iResult = sqlite3_step(pp_stmt);
        if(iResult != SQLITE_DONE){
            iRes = sqlite3_finalize(pp_stmt);
        }
    }else {
        NSLog(@"更新失败");
        iRes = SQLITE_ERROR;
    }
    
    return iRes;
}

- (int)updateSubModel:(id)sub_model_object where:(NSString *)where subModelName:(NSString *)sub_model_name replaceNil:(BOOL)replaceNil{
    int iRes = SQLITE_OK;
    
    if (![self openTable:[sub_model_object class]])
        return SQLITE_ERROR;
    
    iRes = [self commonUpdateModel:sub_model_object where:where subModelName:sub_model_name replaceNil:replaceNil];
    
    [self closeDatabase];
    
    return iRes;
}

- (NSDictionary *)modifyAssistQuery:(Class)model_class where:(NSString *)where {
    if ([self openTable:model_class]) {
        NSString * table_name = NSStringFromClass(model_class);
        NSString * select_sql = [NSString stringWithFormat:@"SELECT * FROM %@",table_name];
        if (where != nil && where.length > 0) {
            select_sql = [select_sql stringByAppendingFormat:@" WHERE %@",where];
        }
        NSDictionary * sub_model_class_info = [self scanSubModelClass:model_class];
        NSMutableString * sub_model_name = [NSMutableString new];
        [sub_model_class_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            [sub_model_name appendString:key];
            [sub_model_name appendString:@" "];
        }];
        if (sub_model_name.length > 0) {
            [sub_model_name deleteCharactersInRange:NSMakeRange(sub_model_name.length - 1, 1)];
            NSMutableArray * model_object_array = [NSMutableArray array];
            sqlite3_stmt * pp_stmt = nil;
            if (sqlite3_prepare_v2(_edb_database, [select_sql UTF8String], -1, &pp_stmt, nil) == SQLITE_OK) {
                while (sqlite3_step(pp_stmt) == SQLITE_ROW) {
                    int colum_count = sqlite3_column_count(pp_stmt);
                    NSMutableDictionary * sub_model_id_info = [NSMutableDictionary dictionary];
                    for (int column = 1; column < colum_count; column++) {
                        NSString * field_name = [NSString stringWithCString:sqlite3_column_name(pp_stmt, column) encoding:NSUTF8StringEncoding];
                        if ([sub_model_name rangeOfString:field_name].location != NSNotFound) {
                            sqlite3_int64 sub_id = sqlite3_column_int64(pp_stmt, column);
                            [sub_model_id_info setObject:@(sub_id) forKey:field_name];
                        }
                    }
                    [model_object_array addObject:sub_model_id_info];
                }
            }else {
                NSLog(@"Sorry查询语句异常,建议先检查Where条件sql语句语法是否正确");
            }
            sqlite3_finalize(pp_stmt);
            [self closeDatabase];
            return @{sub_model_name: model_object_array};
        }
    }
    return @{};
}

- (int)updateCommonModel:(id)model_object where:(NSString *)where replaceNil:(BOOL)replaceNil{
    int iRes = [self updateSubModel:model_object where:where subModelName:nil replaceNil:replaceNil];
    NSDictionary * queryDictionary = [self modifyAssistQuery:[model_object class] where:where];
    if (queryDictionary.count > 0) {
        NSArray * model_object_array = queryDictionary.allValues.lastObject;
        [model_object_array enumerateObjectsUsingBlock:^(NSDictionary * sub_model_id_info, NSUInteger idx, BOOL * _Nonnull stop) {
            [sub_model_id_info.allKeys enumerateObjectsUsingBlock:^(NSString * field_name, NSUInteger idx, BOOL * _Nonnull stop) {
                
                NSString *_id = sub_model_id_info[field_name];
                id subModel = [model_object valueForKey:field_name];
                
                if ([_id integerValue] == kNoHandleKeyId && subModel) {
                    NSLog(@"还未写入数据，应该是先insert！");
                    
                    [self commonInsertSubModel:subModel forModel:model_object where:where subField:field_name];
                }else{
                    id subModel = [model_object valueForKey:field_name];
                    NSString *subWhere = [NSString stringWithFormat:@"_id = %@",_id];
                    int iRowCount = 0;
                    if ([self openTable:[subModel class]]) {
                        iRowCount = [self commonQueryCountForModelClass:[subModel class] where:where];
                        
                        [self closeDatabase];
                    }
                    
                    if (iRowCount>1) {
                        [self updateCommonModel:subModel where:subWhere replaceNil:replaceNil];
                    }else{
                        //更新失败，插入数据库
                        sqlite3_int64 idx = [self commonInsertSubModel:subModel forModel:model_object where:where subField:field_name];
                        if(idx<=0){
                            NSLog(@"update subModel:%@ failed",subModel);
                        }
                    }
                }
            }];
        }];
    }
    
    return iRes;
}

#pragma mark - delete
- (BOOL)commonDeleteModelClass:(Class)model_class where:(NSString *)where {
    BOOL result = NO;
    if ([self openTable:model_class]) {
        NSString * table_name = NSStringFromClass(model_class);
        NSString * delete_sql = [NSString stringWithFormat:@"DELETE FROM %@",table_name];
        if (where != nil && where.length > 0) {
            delete_sql = [delete_sql stringByAppendingFormat:@" WHERE %@",where];
        }
        result = [self execSql:delete_sql];
        [self closeDatabase];
    }
    return result;
}

- (void)deleteModelClass:(Class)model_class where:(NSString *)where {
    if (where != nil && where.length > 0) {
        NSDictionary * queryDictionary = [self modifyAssistQuery:model_class where:where];
        NSDictionary * subModelInfo = [self scanSubModelClass:model_class];
        if (queryDictionary.count > 0) {
            NSArray * model_object_array = queryDictionary.allValues.lastObject;
            if ([self commonDeleteModelClass:model_class where:where]) {
                [model_object_array enumerateObjectsUsingBlock:^(NSDictionary * sub_model_id_info, NSUInteger idx, BOOL * _Nonnull stop) {
                    [sub_model_id_info.allKeys enumerateObjectsUsingBlock:^(NSString * field_name, NSUInteger idx, BOOL * _Nonnull stop) {
                        [self deleteModelClass:NSClassFromString(subModelInfo[field_name]) where:[NSString stringWithFormat:@"_id = %@",sub_model_id_info[field_name]]];
                    }];
                }];
            }
        }else {
            goto DELETE;
        }
    }else {
    DELETE:
        if ([self commonDeleteModelClass:model_class where:where]) {
            NSDictionary * sub_model_class_info = [self scanSubModelClass:model_class];
            [sub_model_class_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
                [self deleteModelClass:NSClassFromString(obj) where:where];
            }];
        }
    }
}

- (BOOL)commonDeleteSubModel:(id)model where:(NSString *)where{
    BOOL result = NO;
    
    NSString * table_name = NSStringFromClass([model class]);
    
    if (where.length <= 0) {
        where = [self allPrimaryKeyWhereSQLForModel:model];
    }
    
    NSString * delete_sql = [NSString stringWithFormat:@"DELETE FROM %@",table_name];
    if (where != nil && where.length > 0) {
        delete_sql = [delete_sql stringByAppendingFormat:@" WHERE %@",where];
        result = [self execSql:delete_sql];
    }else{
        NSLog(@"%@未定义主键",model);
    }
    
    return result;
}

- (int)commonDeleteSubModelArray:(NSArray *)models{
    
    int iDeleteCount = 0;
    Class cls = [models.firstObject class];
    
    if (models.count > 0 &&
        [self openTable:cls]) {
        [self execSql:@"BEGIN"];
        
        for (id obj in models) {
            if ([self commonDeleteSubModel:obj where:nil]) {
                iDeleteCount += 1;
            }
        }
        
        [self execSql:@"COMMIT"];
        [self closeDatabase];
    }
    
    return iDeleteCount;
}

- (int)deleteSubModelArray:(NSArray *)models{
    [models enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        NSDictionary * sub_model_object_info = [self scanSubModelObject:obj];
        
        if (sub_model_object_info.count > 0) {
            //找出_id关键字做删除
            NSDictionary * queryDictionary = [self modifyAssistQuery:[obj class] where:[self allPrimaryKeyWhereSQLForModel:obj]];
            
            NSArray * model_object_array = queryDictionary.allValues.lastObject;
            [model_object_array enumerateObjectsUsingBlock:^(NSDictionary * sub_model_id_info, NSUInteger idx, BOOL * _Nonnull stop) {
                [sub_model_id_info.allKeys enumerateObjectsUsingBlock:^(NSString * field_name, NSUInteger idx, BOOL * _Nonnull stop) {
                    NSString *_id = sub_model_id_info[field_name];
                    id subModel = [obj valueForKey:field_name];
                    [self deleteModelClass:[subModel class] where:[NSString stringWithFormat:@"_id = %@",_id]];
                }];
            }];
        }
    }];
    
    return [self commonDeleteSubModelArray:models];
}

#pragma mark - remove
- (void)removeSubModel:(Class)model_class {
    NSFileManager * file_manager = [NSFileManager defaultManager];
    NSDictionary * sub_model_class_info = [self scanSubModelClass:model_class];
    [sub_model_class_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        Class sub_model_calss = NSClassFromString(obj);
        [self removeSubModel:sub_model_calss];
        NSString * file_path = [self localPathWithClass:sub_model_calss];
        if (file_path) {
            [file_manager removeItemAtPath:file_path error:nil];
        }
    }];
}

#pragma mark - public method

- (instancetype)initWithDataBaseDir:(NSString *)dir{
    self = [self init];
    if (self) {
        if (![dir hasSuffix:@"/"]) {
            //分割符
            self.dbWorkSpace = [dir stringByAppendingString:@"/"];
        }else{
            self.dbWorkSpace = dir;
        }
    }
    
    return self;
}

- (instancetype)initWithDatabBaseDir:(NSString *)dir privateKey:(NSString *)key{
    self = [self initWithDataBaseDir:dir];
    if (self) {
        if (key) {
            [self.encryptKeys setValue:key forKey:kEDBEncryptKeyNormalClass];
        }
    }
    
    return self;
}

- (void)closeDatabase{
    if (_edb_database) {
        sqlite3_close(_edb_database);
        _edb_database = nil;
    }
}

- (EKOSError)openDataBase:(NSString *)path encryptKey:(NSString *)key{
    if(sqlite3_open([path UTF8String], &_edb_database) == SQLITE_OK){
        //是否数据库加密了
        if (key) {
#if EKODATABASE_ENABLE_ENCRYPT
            NSData *keyData = [NSData dataWithBytes:[key UTF8String] length:(NSUInteger)strlen([key UTF8String])];
            if (keyData) {
                if(sqlite3_key(_edb_database, [keyData bytes], (int)[keyData length]) == SQLITE_OK){
                    return EKOSErrorNone;
                }else{
                    return EKOSErrorEncryptFail;
                }
            }
#else
            return EKOSErrorEncryptNotSupported;
#endif
        }else{
            return EKOSErrorNone;
        }
    }
    
    return EKOSErrorUnknown;
}

- (EKOSError)removeEncryptKey:(NSString *)key ofModelClass:(Class)cls{
    EKOSError result = EKOSErrorUnknown;
#if EKODATABASE_ENABLE_ENCRYPT
    NSString *path = [self localPathWithClass:cls];
    if (path) {
        result = [self openDataBase:path encryptKey:key];
        if (result == EKOSErrorNone) {
            if (sqlite3_rekey(_edb_database, NULL, 0) == SQLITE_OK) {
                result = EKOSErrorNone;
            }
        }
    }
    
    //操作完成之后，关闭当前数据库
    [self closeDatabase];
#else
    result = EKOSErrorEncryptNotSupported;
#endif
    [self setEncryptKey:nil forClass:cls];
    
    return result;
}

- (EKOSError)resetEncryptKey:(NSString *)key withOriginalKey:(NSString *)oKey ofModelClass:(__unsafe_unretained Class)cls{
    EKOSError result = EKOSErrorUnknown;
    
#if EKODATABASE_ENABLE_ENCRYPT
    
    NSString *path = [self localPathWithClass:cls];
    if (path) {
        result = [self openDataBase:path encryptKey:oKey];
        if (result == EKOSErrorNone) {
            if (key) {
                NSData *keyData = [NSData dataWithBytes:[key UTF8String] length:(NSUInteger)strlen([key UTF8String])];
                if (keyData) {
                    if(sqlite3_rekey(_edb_database, [keyData bytes], (int)[keyData length]) == SQLITE_OK){
                        result = EKOSErrorNone;
                    }else{
                        result = EKOSErrorEncryptFail;
                    }
                }
            }else{
                //Remove encrypt key
                if (sqlite3_rekey(_edb_database, NULL, 0) == SQLITE_OK) {
                    result = EKOSErrorNone;
                }
            }
        }
    }
    
    [self closeDatabase];

#else
    result = EKOSErrorEncryptNotSupported;
#endif
    
    [self setEncryptKey:key forClass:cls]; //重新设置了新的密码
    
    return result;
}

- (EKOSError)insertModel:(id)model{
    EKOSError result = EKOSErrorNone;
    do {
        NSString *_id = [self performFunc:kDefaultPrimaryKey forModel:model];
        if (_id) {
            //有关键字，需要update
            result = [self updateModel:model where:[NSString stringWithFormat:@"%@=%@",kDefaultPrimaryKey,_id]];
        
            if (result == EKOSErrorNone) {
                break;
            }
        }
        
        dispatch_semaphore_wait(self.dsema, DISPATCH_TIME_FOREVER);
        @autoreleasepool {
            [self.sub_model_info removeAllObjects];
            if([self insertModelObject:model]<0){
                result = EKOSErrorUnknown;
            }
        }
        dispatch_semaphore_signal(self.dsema);
    }while(0);
    
    return result;
}

- (EKOSError)insertModels:(NSArray *)models{
    dispatch_semaphore_wait(self.dsema, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        [self.sub_model_info removeAllObjects];
        if (models != nil && models.count > 0) {
            [self inserSubModelArray:models];
        }
    }
    dispatch_semaphore_signal(self.dsema);
    
    return EKOSErrorNone;
}

- (NSArray *)queryByClass:(Class)cls where:(id)where order:(NSString *)order limit:(NSString *)limit{
    return [self queryModel:cls conditions:@[where == nil ? @"" : [self genSQLWithWhere:where],
                                                     order == nil ? @"" : order,
                                                     limit == nil ? @"" : limit] queryType:_WhereOrderLimit];
}
- (NSArray *)queryByClass:(Class)cls order:(NSString *)order limit:(NSString *)limit{
    return [self queryModel:cls conditions:@[order == nil ? @"" : order,
                                             limit == nil ? @"" : limit] queryType:_OrderLimit];
}
- (NSArray *)queryByClass:(Class)cls where:(id)where order:(NSString *)order{
    return [self queryModel:cls conditions:@[where == nil ? @"" : [self genSQLWithWhere:where],
                                                     order == nil ? @"" : order] queryType:_WhereOrder];
}
- (NSArray *)queryByClass:(Class)cls where:(id)where limit:(NSString *)limit{
    return [self queryModel:cls conditions:@[where == nil ? @"" : [self genSQLWithWhere:where],
                                                     limit == nil ? @"" : limit] queryType:_WhereLimit];
}
- (NSArray *)queryByClass:(Class)cls where:(id)where{
    return [self queryModel:cls conditions:@[where == nil ? @"" : [self genSQLWithWhere:where]] queryType:_Where];
}
- (NSArray *)queryByClass:(Class)cls limit:(NSString *)limit{
    return [self queryModel:cls conditions:@[limit == nil ? @"" : limit] queryType:_Limit];
}
- (NSArray *)queryByClass:(Class)cls order:(NSString *)order{
    return [self queryModel:cls conditions:@[order == nil ? @"" : order] queryType:_Order];
}

- (NSArray *)queryByClass:(Class)cls{
    return [self queryByClass:cls where:nil];
}

- (NSArray *)queryByClass:(Class)cls withFields:(NSDictionary *)fields{
    NSString *where = [self genSQLWithWhere:fields];
    
    if (where) {
        return [self queryByClass:cls where:where];
    }
    
    return nil;
}

- (id)querySingleByClass:(Class)cls where:(id)where{
    NSArray *results = [self queryByClass:cls where:where limit:@"1"];
    if (results.count>0) {
        return [results objectAtIndex:0];
    }
    
    return nil;
}

- (id)querySingleByClass:(Class)cls where:(id)where order:(NSString *)order{
    NSArray *results = [self queryByClass:cls where:where order:order limit:@"1"];
    if (results.count>0) {
        return [results objectAtIndex:0];
    }
    
    return nil;
}

- (NSInteger)queryCountByClass:(Class)cls where:(NSString *)where{
    NSInteger iCount = 0;
    dispatch_semaphore_wait(self.dsema, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        if ([self openTable:cls]) {
            iCount = [self commonQueryCountForModelClass:cls where:where];
            
            [self closeDatabase];
        }
    }
    dispatch_semaphore_signal(self.dsema);
    
    return iCount;
}

- (EKOSError)updateModel:(id)model replaceNil:(BOOL)replaceNil{
    //通过主键更新
    NSString *primaryKeySQL = [self primaryKeyWhereSQLForModel:model];
    if ([primaryKeySQL length]>0) {
        return [self updateModel:model where:primaryKeySQL replaceNil:replaceNil];
    }
    
    NSString *_id = [self performFunc:kDefaultPrimaryKey forModel:model];
    if (!_id) {
        return EKOSErrorConditionNone;
    }
    
    return [self updateModel:model where:[NSString stringWithFormat:@"%@=%@",kDefaultPrimaryKey,_id] replaceNil:replaceNil];
}

- (EKOSError)updateModel:(id)model where:(NSString *)where replaceNil:(BOOL)replaceNil{
    dispatch_semaphore_wait(self.dsema, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        [self.sub_model_info removeAllObjects];
        [self updateCommonModel:model where:where replaceNil:replaceNil];
    }
    dispatch_semaphore_signal(self.dsema);
    
    return EKOSErrorNone;
}

- (EKOSError)updateModel:(id)model{
    return [self updateModel:model replaceNil:NO];
}

- (EKOSError)updateModel:(id)model where:(NSString *)where{
    return [self updateModel:model where:where replaceNil:NO];
}

- (EKOSError)clearByClass:(Class)cls{
    return [self deleteByClass:cls where:nil];
}

- (EKOSError)deleteByClass:(Class)cls where:(NSString *)where{
    dispatch_semaphore_wait(self.dsema, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        [self.sub_model_info removeAllObjects];
        [self deleteModelClass:cls where:where];
    }
    dispatch_semaphore_signal(self.dsema);
    
    return EKOSErrorNone;
}

- (EKOSError)deleteByModel:(id)model{
    EKOSError result = EKOSErrorNone;
    
    NSString *where = nil;
    NSString *_id = [self performFunc:kDefaultPrimaryKey forModel:model];
    if (_id) {
        //有关键字，需要update
        where = [NSString stringWithFormat:@"%@=%@",kDefaultPrimaryKey,_id];
    }else{
        where = [self primaryKeyWhereSQLForModel:model];
    }
    
    if (where && where.length>0) {
        result = [self deleteByClass:[model class] where:where];
    }else{
        result = EKOSErrorPrimaryKeyLack;
    }
    
    return EKOSErrorNone;
}

- (NSInteger)deleteByModels:(NSArray *)models{
    NSInteger result = 0;
    
    dispatch_semaphore_wait(self.dsema, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        [self.sub_model_info removeAllObjects];
        result = [self deleteSubModelArray:models];
    }
    dispatch_semaphore_signal(self.dsema);
    
    return result;
}

- (EKOSError)removeAll{
    dispatch_semaphore_wait(self.dsema, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        NSFileManager * file_manager = [NSFileManager defaultManager];
        NSString * cache_path = [self databaseCacheDirectory];
        BOOL is_directory = YES;
        if ([file_manager fileExistsAtPath:cache_path isDirectory:&is_directory]) {
            NSArray * file_array = [file_manager contentsOfDirectoryAtPath:cache_path error:nil];
            [file_array enumerateObjectsUsingBlock:^(id  _Nonnull file, NSUInteger idx, BOOL * _Nonnull stop) {
                if (![file isEqualToString:@".DS_Store"]) {
                    NSString * file_path = [NSString stringWithFormat:@"%@%@",cache_path,file];
                    [file_manager removeItemAtPath:file_path error:nil];
                    NSLog(@"已经删除了数据库 ->%@",file_path);
                }
            }];
        }
    }
    dispatch_semaphore_signal(self.dsema);
    
    return EKOSErrorNone;
}

- (EKOSError)removeByClass:(Class)cls{
    dispatch_semaphore_wait(self.dsema, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        NSFileManager * file_manager = [NSFileManager defaultManager];
        NSString * file_path = [self localPathWithClass:cls];
        if (file_path) {
            [self removeSubModel:cls];
            [file_manager removeItemAtPath:file_path error:nil];
        }
    }
    dispatch_semaphore_signal(self.dsema);
    
    return EKOSErrorNone;
}

- (NSString *)versionOfClass:(Class)cls{
    NSString * model_version = nil;
    NSString * model_name = [self localNameWithClass:cls];
    if (model_name) {
        NSRange end_range = [model_name rangeOfString:@"." options:NSBackwardsSearch];
        NSRange start_range = [model_name rangeOfString:@"v" options:NSBackwardsSearch];
        if (end_range.location != NSNotFound &&
            start_range.location != NSNotFound) {
            model_version = [model_name substringWithRange:NSMakeRange(start_range.length + start_range.location, end_range.location - (start_range.length + start_range.location))];
        }
    }
    return model_version;
}

- (EKOSError)saveByValue:(NSDictionary *)dict intoTable:(NSString *)tableName{
    EKOSError result = EKOSErrorUnknown;
    
    NSString * cache_directory = [self databaseCacheDirectory];
    BOOL is_directory = YES;
    if (![[NSFileManager defaultManager] fileExistsAtPath:cache_directory isDirectory:&is_directory]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:cache_directory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSString * database_cache_path = [NSString stringWithFormat:@"%@%@.sdb",cache_directory,tableName];
    
    do {
        if ([self openDataBase:database_cache_path encryptKey:[self encryptKeyForClass:nil]] == EKOSErrorNone) {
            
            if (![self createTable:tableName fields:[self parseFieldsWithValues:dict] primaryKeys:nil]) {
                NSLog(@"Cannot create table!");
                result = EKOSErrorUnknown;
                break;
            }
            
            NSArray *keys = [dict allKeys];
            NSArray *values = [dict allValues];
            NSString * sql;
            NSMutableDictionary *tempKeyValues = [NSMutableDictionary dictionaryWithDictionary:dict];
            if ([tempKeyValues valueForKey:kDefaultPrimaryKey] != nil) {
                int idUpdate = [[tempKeyValues valueForKey:kDefaultPrimaryKey] intValue];
                NSString *updateSql = @"";
                for (NSString *key in keys) {
                    if (![key isEqualToString:kDefaultPrimaryKey]) {
                        updateSql = [NSString stringWithFormat:@"%@,%@=?",updateSql,key];
                    }
                }
                updateSql = [updateSql substringFromIndex:1];
                sql = [NSString stringWithFormat:@"UPDATE %@ SET %@ WHERE id=%d",tableName, updateSql, idUpdate];
                [tempKeyValues removeObjectForKey:kDefaultPrimaryKey];
                values = [dict allValues];
            }
            else{
                NSString *keysSql = @"";
                NSString *valuesSql = @"";
                for (NSString *key in keys) {
                    keysSql = [NSString stringWithFormat:@"%@,%@",keysSql,key];
                    valuesSql = [NSString stringWithFormat:@"%@,?",valuesSql];
                }
                keysSql = [keysSql substringFromIndex:1];
                valuesSql = [valuesSql substringFromIndex:1];
                sql = [NSString stringWithFormat:@"INSERT INTO %@ (%@) VALUES (%@)",tableName, keysSql, valuesSql];
            }
            const char *sqlStatement = (const char*)[sql UTF8String];
            sqlite3_stmt *compiledStatement;
            if(sqlite3_prepare_v2(_edb_database, sqlStatement, -1, &compiledStatement, NULL) == SQLITE_OK) {
                int index = 1;
                for (NSString * value in values) {
                    if( [[NSScanner scannerWithString:(NSString *)value] scanFloat:NULL] ){
                        sqlite3_bind_int(compiledStatement, index, [(NSString*)value intValue]);
                    }
                    else {
                        sqlite3_bind_text(compiledStatement, index, [(NSString *)value UTF8String], -1, SQLITE_TRANSIENT);
                    }
                    index++;
                }
                if(SQLITE_DONE != sqlite3_step(compiledStatement)) {
                    NSLog(@"Error sqlite3_step :. '%s'", sqlite3_errmsg(_edb_database));
                    result = EKOSErrorUnknown;
                }else{
                    sqlite3_finalize(compiledStatement);
                    result = EKOSErrorNone;
                }
            }
            else {
                NSLog(@"Error sqlite3_prepare_v2 :. '%s'", sqlite3_errmsg(_edb_database));
                result = EKOSErrorUnknown;
            }
        }
    }while(0);

    [self closeDatabase];
    
    return result;
}

- (NSArray *)findfromTable:(NSString *)tableName{
    NSArray *result = nil;
    
    dispatch_semaphore_wait(self.dsema, DISPATCH_TIME_FOREVER);
    
    NSString * cache_directory = [self databaseCacheDirectory];
    
    NSString * database_cache_path = [NSString stringWithFormat:@"%@%@.sdb",cache_directory,tableName];
    if ([self openDataBase:database_cache_path encryptKey:[self encryptKeyForClass:nil]] == EKOSErrorNone) {
        NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@",tableName];
        result = [self findBySql:sql];
    }
    
    [self closeDatabase];
    dispatch_semaphore_signal(self.dsema);
    
    return result;
}

#pragma mark - getters and setters
- (NSMutableDictionary *)encryptKeys{
    if (!_encryptKeys) {
        _encryptKeys = [NSMutableDictionary dictionary];
    }
    
    return _encryptKeys;
}

- (NSString *)encryptKeyForClass:(Class)cls{
    NSString *value = nil;
    if (cls) {
        NSString *clsName = NSStringFromClass(cls);
        value = [self.encryptKeys valueForKey:clsName];
    }
    
    if (!value) {
        value = [self.encryptKeys valueForKey:kEDBEncryptKeyNormalClass];
    }
    
    return value;
}

- (void)setEncryptKey:(NSString *)key forClass:(Class)cls{
    if (!cls) {
        NSString *clsName = NSStringFromClass(cls);
        [self.encryptKeys setValue:key forKey:clsName];
    }
}


/**
 由于有些系统类不能setvalue forKey，会导致异常
 需要判断是否支持的基本类型

 @param cls 类
 @return 是否可以保存到数据库
 */
- (BOOL)isSupportClass:(Class)cls{
    NSArray *validateCls = @[
                         [NSString class],
                         [NSNumber class],
                         [NSArray class],
                         [NSSet class],
                         [NSData class],
                         [NSDate class],
                         [NSDictionary class],
                         [NSValue class],
                         [NSError class]
                         ];
    BOOL bRes = NO;
    
    for (Class c in validateCls) {
        if (cls == c) {
            bRes = YES;
            break;
        }
    }
    
    return bRes;
}

- (NSString *)parsePropertyName:(NSString *)attribute{
    NSString *propertyType = nil;
    
    NSInteger isOptional = 0;
    
    if ([attribute containsString:@"<"]) {
        //设置了属性，做过滤处理
        NSScanner *scanner = [NSScanner scannerWithString:attribute];
        if ([scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"<"]
                                    intoString:&propertyType]) {
            
            while ([scanner scanString:@"<" intoString:nil]) {
                NSString* protocolName = nil;
                
                [scanner scanUpToString:@">" intoString: &protocolName];
                
                if ([protocolName isEqualToString:@"Optional"]) {
                    isOptional = 1;
                } else if([protocolName isEqualToString:@"Ignore"]) {
                    isOptional = 2;
                } else {
                    NSLog(@"unknown protocol:%@",protocolName);
                }
                
                [scanner scanString:@">" intoString:NULL];
            }
        }
    }else {
        propertyType = attribute;
    }
    
    if (isOptional == 2) {
        //Ignore
        //continue;
    }else if(isOptional == 1){
        //TODO
    }
    
    return propertyType;
}

@end
