//
//  NSArray+NSArrayAdditions.h
//  STRyper
//
//  Created by Jean Peccoud on 27/10/2023.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSArray (NSArrayAdditions)


-(NSArray *)sortedArrayUsingKey:(NSString *)key ascending:(BOOL)ascending;

@end

NS_ASSUME_NONNULL_END
