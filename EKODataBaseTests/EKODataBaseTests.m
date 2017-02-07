//
//  EKODataBaseTests.m
//  EKODataBaseTests
//
//  Created by kingo on 25/01/2017.
//  Copyright © 2017 XTC. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "EKOSQLiteMgr.h"

@interface TestModel : NSObject

@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSString *telphone;
@property (nonatomic, readonly) NSString *_id;

@property (nonatomic, retain) NSString *userId;
@property (nonatomic, retain) NSString *nameId;

+ (NSString *)VERSION;

@end

@interface TestModelFirst : NSObject<NSCoding>

@property (nonatomic, retain) NSString *n1;
@property (nonatomic, retain) NSString *u1;

@end

@interface TestModelSecond : NSObject

@property (nonatomic, retain) NSString *n2;
@property (nonatomic, retain) TestModelFirst *first;

@property (nonatomic, strong) NSArray *firsts; //数组

@end

@interface TestModelThird : NSObject

@property (nonatomic, retain) NSString *n3;
@property (nonatomic, retain) NSDictionary *d3;

@end

@interface TestModelEncrypt : NSObject

@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSString *telphone;

+ (NSString *)PASSWORD;

@end

#pragma mark - unionPrimaryKeys

@interface TestModelUnion : NSObject

@property (nonatomic, strong) NSString *userId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *telephone;

@end

@interface EKODataBaseTests : XCTestCase

@property (nonatomic, retain) EKOSQLiteMgr *mgr;

@end

@implementation EKODataBaseTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testExample {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
}

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}

- (void)testDBInsert{
    
    [self.mgr removeByClass:[TestModel class]];
    
    TestModel *model = [[TestModel alloc] init];
    model.name = @"test";
    model.telphone = @"123456789";
    
    EKOSError error = [self.mgr insertModel:model];
    NSLog(@"error=%ld",(long)error);
    
    TestModel *model2 = [[TestModel alloc] init];
    [self.mgr insertModel:model2];
    
    TestModel *m3 = [[TestModel alloc] init];
    m3.userId = @"u3";
    [self.mgr insertModel:m3];
    
    NSArray *results = [self.mgr queryByClass:[model class]];
    [results enumerateObjectsUsingBlock:^(TestModel *obj,NSUInteger idx,BOOL *stop){
        NSLog(@"inserted obj:(id=%@)%@,%@",obj._id,obj.name,obj.telphone);
    }];
    
    XCTAssertNotNil(results);
}

- (void)testQueryAll{
    NSArray *results = [self.mgr queryByClass:[TestModel class]];
    [results enumerateObjectsUsingBlock:^(TestModel *obj,NSUInteger idx,BOOL *stop){
        NSLog(@"inserted obj:%@,%@",obj.name,obj.telphone);
    }];
}

- (void)testDBUpdate{
    NSArray *results = [self.mgr queryByClass:[TestModel class]];
    if ([results count]>0) {
        [results enumerateObjectsUsingBlock:^(TestModel *model,NSUInteger idx,BOOL *stop){
            model.name = model.name?([model.name stringByAppendingString:@"_update"]):@"update";
            //有定义_id字段，update和insert是同样的效果
            //[self.mgr updateModel:model];
            [self.mgr updateModel:model replaceNil:YES];
        }];
    }
    
    [self testQueryAll];
}

- (void)testDBRemove{
    
    [self.mgr removeByClass:[TestModel class]];
}

- (void)testDBQuery{
    NSArray *results = [self.mgr queryByClass:[TestModel class] where:@"name = 'test'"];
    [results enumerateObjectsUsingBlock:^(TestModel *obj,NSUInteger idx,BOOL *stop){
        NSLog(@"%ld:queryed obj:%@,%@\r",idx,obj.name,obj.telphone);
    }];
}

//encrypt
- (void)testDBEncrypt{
    //EKOSError result= [self.mgr resetEncryptKey:kTestEncryptKey withOriginalKey:nil ofModelClass:[TestModelEncrypt class]];
    TestModelEncrypt *model = [[TestModelEncrypt alloc] init];
    model.name = @"encrypt1";
    
    [self.mgr insertModel:model];
    NSArray *results = [self.mgr queryByClass:[TestModelEncrypt class]];
    XCTAssertTrue([results count]>0);
    [results enumerateObjectsUsingBlock:^(TestModel *obj,NSUInteger idx,BOOL *stop){
        NSLog(@"%ld:queryed obj:%@,%@\r",idx,obj.name,obj.telphone);
    }];
}

//插入查询字典形数据
- (void)testInsertDict{
    [self.mgr saveByValue:@{@"k1":@"v1",@"k2":@"v2"} intoTable:@"TestDict"];
    
    NSArray *results = [self.mgr findfromTable:@"TestDict"];
    [results enumerateObjectsUsingBlock:^(NSDictionary *dict,NSUInteger idx,BOOL *stop){
        NSLog(@"%ld:queryed obj:%@\r",idx,dict);
    }];
}

#pragma mark - 嵌套
- (void)testDBEmbeddedModel{
    
    [self.mgr removeByClass:[TestModelSecond class]];
    
    TestModelSecond *model = [[TestModelSecond alloc] init];
    model.n2 = @"n2";
    model.first = [[TestModelFirst alloc] init];
    model.first.n1 = @"n1";
    model.first.u1 = @"u1";
    
    TestModelFirst *first1,*first2;
    first1 = [[TestModelFirst alloc] init];
    first2 = [[TestModelFirst alloc] init];
    first1.n1 = @"array_n1";
    first2.n1 = @"array_n2";
    
    model.firsts = @[first1,first2];
    
    [self testModel:model];
}

- (void)testDBModelDictionry{
    TestModelThird *model = [[TestModelThird alloc] init];
    model.n3 = @"n3";
    model.d3 = @{@"d31":@"v31",@"d32":@"v32"};
    
    [self testModel:model];
}

- (void)testModel:(id)model{
    EKOSError error = [self.mgr insertModel:model];
    
    XCTAssertTrue(error == EKOSErrorNone);
    
    NSArray *results = [self.mgr queryByClass:[model class]];
    NSLog(@"result count :%ld",(long)[results count]);
    [results enumerateObjectsUsingBlock:^(id model,NSUInteger idx,BOOL *stop){
        NSLog(@"model :%@",model);
    }];
}

- (void)testDBUnionPrimaryKey{
    
    TestModelUnion *model = [[TestModelUnion alloc] init];
    
    [self.mgr removeByClass:[model class]];
    
    model.userId = @"123456";
    model.telephone = @"111";
    model.name = @"name1";
    
    TestModelUnion *model2 = [[TestModelUnion alloc] init];
    model2.userId = @"123456";
    model2.telephone = @"111";
    model2.name = @"name2";
    
    [self testModel:model];
    [self testModel:model2];
}

- (void)testDBAlter{
    //[self.mgr removeByClass:[TestModel class]];
    
    TestModel *model = [[TestModel alloc] init];
    
    model.userId = @"2";
    
    model.nameId = @"nameId";
    
    [self testModel:model];
}

#pragma mark - getters
- (EKOSQLiteMgr *)mgr{
    if (!_mgr) {
        _mgr = [[EKOSQLiteMgr alloc] init];
    }
    
    return _mgr;
}

@end


@implementation TestModel

+ (NSString *)VERSION{
    return @"1.0";
}

@end

@implementation TestModelEncrypt

+ (NSString *)PASSWORD{
    return @"123456";
}

@end

@implementation TestModelFirst

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:self.n1 forKey:@"n1"];
    [aCoder encodeObject:self.u1 forKey:@"u1"];
}

- (id)initWithCoder:(NSCoder *)aDecoder{
    self = [super init];
    if (self) {
        self.n1 = [aDecoder decodeObjectForKey:@"n1"];
        self.u1 = [aDecoder decodeObjectForKey:@"u1"];
    }
    
    return self;
}

@end

@implementation TestModelSecond

@end


@implementation TestModelThird


@end


@implementation TestModelUnion

+ (NSArray *)unionPrimaryKeys{
    return @[@"userId",@"telephone"];
}

@end
