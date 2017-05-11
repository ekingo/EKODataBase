//
//  EKOSQLiteMgr+Async.m
//  EKODataBase
//
//  Created by kingo on 02/05/2017.
//  Copyright © 2017 XTC. All rights reserved.
//

#import "EKOSQLiteMgr+Async.h"

@implementation EKOSQLiteMgr (Async)

- (void)insertModel:(id)model withBlock:(void (^)(EKOSError))block{
    typeof(self) __weak weakSelf = self;
    [self addOperation:^(){
        EKOSError error = [weakSelf insertModel:model];
        if (block) {
            block(error);
        }
    }];
}

- (void)insertModels:(id)models withBlock:(void (^)(EKOSError))block{
    typeof(self) __weak weakSelf = self;
    [self addOperation:^(){
        EKOSError error = [weakSelf insertModels:models];
        if (block) {
            block(error);
        }
    }];
}

- (void)queryByClass:(Class)cls where:(id)where order:(NSString *)order limit:(NSString *)limit withBlock:(void (^)(NSArray *))block{
    if (!block) {
        return;
    }
    
    typeof(self) __weak weakSelf = self;
    [self addOperation:^(){
        NSArray *results = [weakSelf queryByClass:cls where:where order:order limit:limit];
        if (block) {
            block(results);
        }
    }];
}

- (void)queryByClass:(Class)cls withBlock:(void (^)(NSArray *))block{
    if (!block) {
        return;
    }
    
    typeof(self) __weak weakSelf = self;
    [self addOperation:^(){
        NSArray *results = [weakSelf queryByClass:cls];
        if (block) {
            block(results);
        }
    }];
}

- (void)queryByClass:(Class)cls where:(id)where withBlock:(void (^)(NSArray *))block{
    if (!block) {
        return;
    }
    
    typeof(self) __weak weakSelf = self;
    [self addOperation:^(){
        NSArray *results = [weakSelf queryByClass:cls where:where];
        if (block) {
            block(results);
        }
    }];
}

- (void)queryCountByClass:(Class)cls where:(id)where witheBlock:(void (^)(NSInteger))block{
    if (!block) {
        return;
    }
    
    typeof(self) __weak weakSelf = self;
    [self addOperation:^(){
        NSInteger count = [weakSelf queryCountByClass:cls where:where];
        if (block) {
            block(count);
        }
    }];
}

- (void)updateModel:(id)model where:(id)where withBlock:(void (^)(EKOSError))block{
    typeof(self) __weak weakSelf = self;
    [self addOperation:^(){
        EKOSError error = [weakSelf updateModel:model where:where];
        if (block) {
            block(error);
        }
    }];
}

- (void)updateModel:(id)model where:(id)where replaceNil:(BOOL)replaceNil withBlock:(void (^)(EKOSError))block{
    typeof(self) __weak weakSelf = self;
    [self addOperation:^(){
        EKOSError error = [weakSelf updateModel:where replaceNil:replaceNil];
        if (block) {
            block(error);
        }
    }];
}

- (void)deleteByClass:(Class)cls where:(id)where withBlock:(void (^)(EKOSError))block{
    typeof(self) __weak weakSelf = self;
    [self addOperation:^(){
        EKOSError error = [weakSelf deleteByClass:cls where:where];
        if (block) {
            block(error);
        }
    }];
}

- (void)deleteByModel:(id)model withBlock:(void (^)(EKOSError))block{
    typeof(self) __weak weakSelf = self;
    [self addOperation:^(){
        EKOSError error = [weakSelf deleteByModel:model];
        if (block) {
            block(error);
        }
    }];
}

@end
