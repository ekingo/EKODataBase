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

@property (nonatomic, assign) NSInteger flag;
@property (nonatomic, assign) BOOL bFlag;

@property (nonatomic, strong) NSError *error;

@property (nonatomic, strong) NSArray<NSString *> *array;

+ (NSString *)VERSION;

@end

@interface TestModelFirst : NSObject

@property (nonatomic, retain) NSString *n1;
@property (nonatomic, retain) NSString *u1;

@property (nonatomic, assign) NSInteger flag;

@end

@interface TestModelSecond : NSObject

@property (nonatomic, readonly) NSString *_id;
@property (nonatomic, strong) NSString *userId;

@property (nonatomic, retain) NSString *n2;
@property (nonatomic, retain) TestModelFirst *first;

@property (nonatomic, strong) NSArray *firsts; //数组

@property (nonatomic, strong) NSDictionary *dicts;

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

@interface TestModelInherit : TestModel

@property (nonatomic, strong) NSString *inherited;

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
    model.flag = 1;
    model.bFlag = NO;
    model.array = @[@"1",@"2"];
    
    EKOSError error = [self.mgr insertModel:model];
    NSLog(@"error=%ld",(long)error);
    
    TestModel *model2 = [[TestModel alloc] init];
    [self.mgr insertModel:model2];
    
    TestModel *m3 = [[TestModel alloc] init];
    m3.userId = @"u3";
    m3.flag = 1;
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
            //model.flag = 111;
            [self.mgr updateModel:model replaceNil:YES];
        }];
    }
    
    [self testQueryAll];
}

- (void)testDBRemove{
    
    [self.mgr removeByClass:[TestModel class]];
}

- (void)testDBQuery{
    NSArray *results = [self.mgr queryByClass:[TestModel class] where:/*@"name = 'test'"*/@{@"name":@"test"}];
    [results enumerateObjectsUsingBlock:^(TestModel *obj,NSUInteger idx,BOOL *stop){
        NSLog(@"%ld:queryed obj:%@,%@\r",idx,obj.name,obj.telphone);
    }];
}

- (void)testDBQueryNull{
    NSArray *results = [self.mgr queryByClass:nil];
    //NSArray *results = [self.mgr queryByClass:[TestModelThird class]];
    
    XCTAssertTrue(results.count<=0);
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
    
    TestModelSecond *first1,*first2;
    first1 = [[TestModelSecond alloc] init];
    first2 = [[TestModelSecond alloc] init];
    first1.n2 = @"array_n1";
    first2.n2 = @"array_n2";
    //first2.flag = 2;
    first1.first = [[TestModelFirst alloc] init];
    first1.first.n1 = @"n2_first_n1";
    
    TestModelSecond *second = [[TestModelSecond alloc] init];
    second.n2 = @"second_n2";
    first1.firsts = @[second];
    
    model.firsts = @[first1,first2];
    //model.firsts = @[@{@"first1":first1,@"first2":first2}];
    
    TestModelFirst *first3 = [[TestModelFirst alloc] init];
    first3.n1 = @"dict_n3";
    
    NSArray *a3 = @[first1,first2,first3];
    
    //model.dicts = @{@"dict":first3};
    model.dicts = @{@"dict":a3};
    
    //model.dicts = @{@"dict":@{@"embedDictKey":@"embedValue"}};
    
    [self testModel:model];
}

- (void)testDBEmbeddedUpdate{
    NSArray *results = [self.mgr queryByClass:[TestModelSecond class]];
    if ([results count]>0) {
        [results enumerateObjectsUsingBlock:^(TestModelSecond *model,NSUInteger idx,BOOL *stop){
            if (!model.first) {
                model.first = [[TestModelFirst alloc] init];
                model.first.n1 = @"n10_update";
            }else{
                model.first.n1 = @"n1_update";
            }
            [self.mgr updateModel:model];
        }];
    }
    
    NSArray *r = [self.mgr queryByClass:[TestModelSecond class]];
    XCTAssert([r count]>0);
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

#pragma mark - InheritedModel
- (void)testDBInheritedModel{
    [self.mgr removeByClass:[TestModelInherit class]];
    
    TestModelInherit *model = [[TestModelInherit alloc] init];
    model.userId = @"userId";
    model.inherited = @"继承模型";
    
    [self testModel:model];
}

#pragma mark - delete
- (void)testDBDelete{
    
    [self.mgr removeByClass:[TestModelSecond class]];
    
    TestModelSecond *model = [[TestModelSecond alloc] init];
    model.userId = @"delete";
    model.n2 = @"test";
    model.first = [[TestModelFirst alloc] init];
    model.first.n1 = @"delete_1_first";
    
    [self.mgr insertModel:model];
    
    TestModelSecond *model2 = [[TestModelSecond alloc] init];
    model2.userId = @"delete2";
    model2.first = [[TestModelFirst alloc] init];
    model2.first.n1 = @"delete_2_first";
    
    [self.mgr insertModel:model2];
    
    NSArray *testInsert = [self.mgr queryByClass:[TestModelSecond class]];
    XCTAssertTrue([testInsert count] == 2);
    
    //EKOSError result = [self.mgr deleteByModel:model];
    
    NSArray *models = [NSArray arrayWithObjects:model,model2, nil];
    
    NSInteger result = [self.mgr deleteByModels:models];
    
    NSArray *tests = [self.mgr queryByClass:[TestModelSecond class]];
    
    XCTAssertTrue(result>0);
}

- (void)testDeleteSubModel{
    
    //[self.mgr removeByClass:[TestModelSecond class]];
    
    TestModelSecond *second = [[TestModelSecond alloc] init];
    second.userId = @"deleteSubModel2";
    second.first = [[TestModelFirst alloc] init];
    second.first.n1 = @"delete_first";
    
    [self.mgr insertModel:second];
    
    [self.mgr removeByClass:[TestModelFirst class]];
    
    NSArray *firsts = [self.mgr queryByClass:[TestModelFirst class]];
    
    XCTAssertTrue([firsts count]<=0);
    
    second.first.n1 = @"deleted_first_after";
    [self.mgr updateModel:second];
    
    NSArray *results = [self.mgr queryByClass:[TestModelSecond class]];
    
    XCTAssertTrue([results count]>0);
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

- (instancetype)init{
    self = [super init];
    if (self) {
        self.error = [NSError errorWithDomain:@"test_database" code:0 userInfo:nil];
    }
    
    return self;
}

+ (NSString *)VERSION{
    return @"1.0";
}

+ (NSArray *)eko_unionPrimaryKeys{
    return @[@"userId"];
}

//+ (NSArray *)eko_ignoreProperties{
//    return @[@"error"];
//}

@end

@implementation TestModelEncrypt

+ (NSString *)PASSWORD{
    return @"123456";
}

@end

@implementation TestModelFirst

//- (void)encodeWithCoder:(NSCoder *)aCoder{
//    [aCoder encodeObject:self.n1 forKey:@"n1"];
//    [aCoder encodeObject:self.u1 forKey:@"u1"];
//}
//
//- (id)initWithCoder:(NSCoder *)aDecoder{
//    self = [super init];
//    if (self) {
//        self.n1 = [aDecoder decodeObjectForKey:@"n1"];
//        self.u1 = [aDecoder decodeObjectForKey:@"u1"];
//    }
//    
//    return self;
//}

@end

@implementation TestModelSecond

+ (NSArray *)eko_unionPrimaryKeys{
    return @[@"userId"];
}

@end


@implementation TestModelThird


@end


@implementation TestModelUnion

+ (NSArray *)eko_unionPrimaryKeys{
    return @[@"userId",@"telephone"];
}

@end


@implementation TestModelInherit

@end
