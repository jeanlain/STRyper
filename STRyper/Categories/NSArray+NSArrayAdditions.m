//
//  NSArray+NSArrayAdditions.m
//  STRyper
//
//  Created by Jean Peccoud on 27/10/2023.
//

#import "NSArray+NSArrayAdditions.h"

@implementation NSArray (NSArrayAdditions)



- (NSArray *)sortedArrayUsingKey:(NSString *)key ascending:(BOOL)ascending {
	NSSortDescriptor *desc = [NSSortDescriptor sortDescriptorWithKey:key ascending:ascending];
	return [self sortedArrayUsingDescriptors:@[desc]];
	
}

@end
