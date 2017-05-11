//
//  EKOSQLiteMgr+Async.h
//  EKODataBase
//
//  Created by kingo on 02/05/2017.
//  Copyright © 2017 XTC. All rights reserved.
//

#import "EKOSQLiteMgr.h"

//所有数据库操作在同一个异步队列中
@interface EKOSQLiteMgr (Async)

//Insert
- (void)insertModel:(id)model withBlock:(void(^)(EKOSError result))block;
- (void)insertModels:(id)models withBlock:(void(^)(EKOSError result))block;

//Query
- (void)queryByClass:(Class)cls where:(id)where order:(NSString *)order limit:(NSString *)limit withBlock:(void(^)(NSArray *results))block;
- (void)queryByClass:(Class)cls withBlock:(void(^)(NSArray *results))block;
- (void)queryByClass:(Class)cls where:(id)where withBlock:(void(^)(NSArray *results))block;

//Query Count
- (void)queryCountByClass:(Class)cls where:(id)where witheBlock:(void(^)(NSInteger count))block;

//Update
- (void)updateModel:(id)model where:(id)where withBlock:(void(^)(EKOSError result))block;
- (void)updateModel:(id)model where:(id)where replaceNil:(BOOL)replaceNil withBlock:(void(^)(EKOSError result))block;

//Delete
- (void)deleteByClass:(Class)cls where:(id)where withBlock:(void(^)(EKOSError result))block;
- (void)deleteByModel:(id)model withBlock:(void(^)(EKOSError result))block;

@end
