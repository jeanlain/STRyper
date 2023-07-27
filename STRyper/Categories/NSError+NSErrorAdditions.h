//
//  NSError+NSErrorAdditions.h
//  STRyper
//
//  Created by Jean Peccoud on 21/01/2023.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.



#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const STRyperErrorDomain;


@interface NSError (NSErrorAdditions)

/// Convenience method to return a generic formatted error with the most basic information.
+ (instancetype)errorWithDescription:(nullable NSString *)description suggestion:(nullable NSString *) suggestion;

/// Convenience method to return a error that describes a cancel operation (as specified in the error code).
+ (instancetype)cancelOperationErrorWithDescription:(nullable NSString *)description suggestion:(nullable NSString *) suggestion;

/// Convenience method to return a error that describes a file read error (as specified in the error code).
+ (instancetype)fileReadErrorWithDescription:(NSString *)description suggestion:(NSString *)suggestion filePath:(NSString *)filePath reason:(NSString *)reason;

/// Convenience method to return a error that describes a managed object validation error (as specified in the error code).
+ (instancetype)managedObjectValidationErrorWithDescription:(NSString *)description suggestion:(NSString *)suggestion object:(id)object reason:(NSString *)reason;

@end

NS_ASSUME_NONNULL_END
