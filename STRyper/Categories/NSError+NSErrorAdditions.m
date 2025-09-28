//
//  NSError+NSErrorAdditions.m
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



#import "NSError+NSErrorAdditions.h"
@import Cocoa;

@implementation NSError (NSErrorAdditions)

NSString *const STRyperErrorDomain = @"jpeccoud.STRyper";

+ (instancetype)errorWithDescription:(NSString *)description suggestion:(NSString *) suggestion {
	NSDictionary *userInfo = @{
		NSLocalizedDescriptionKey: NSLocalizedString(description, nil),
		NSLocalizedFailureReasonErrorKey: NSLocalizedString(description, nil),
		NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(suggestion, nil)
	};
	
	return [self errorWithDomain:STRyperErrorDomain code:42 userInfo:userInfo];  /// error code is arbitrary

}

+ (instancetype)cancelOperationErrorWithDescription:(NSString *)description suggestion:(NSString *)suggestion {
	NSDictionary *userInfo = @{
		NSLocalizedDescriptionKey: NSLocalizedString(description, nil),
		NSLocalizedFailureReasonErrorKey: NSLocalizedString(description, nil),
		NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(suggestion, nil)
	};
	return [self errorWithDomain:STRyperErrorDomain code:NSUserCancelledError userInfo:userInfo];

}

+ (instancetype)fileReadErrorWithDescription:(NSString *)description suggestion:(NSString *)suggestion filePath:(NSString *)filePath reason:(NSString *)reason {
	NSDictionary *userInfo = @{
		NSFilePathErrorKey: NSLocalizedString(filePath, nil),
		NSLocalizedDescriptionKey: NSLocalizedString(description, nil),
		NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(suggestion, nil),
		NSLocalizedFailureReasonErrorKey: NSLocalizedString(reason, nil)
	};
	return [self errorWithDomain:STRyperErrorDomain code:NSFileReadCorruptFileError userInfo:userInfo];

}

+ (instancetype)managedObjectValidationErrorWithDescription:(NSString *)description suggestion:(NSString *)suggestion object:(id)object reason:(NSString *)reason {
	NSDictionary *userInfo = @{
		NSAffectedObjectsErrorKey: object != nil? @[object]:nil,
		NSLocalizedDescriptionKey: NSLocalizedString(description, nil),
		NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(suggestion, nil),
		NSLocalizedFailureReasonErrorKey: NSLocalizedString(reason, nil)
	};
	return [self errorWithDomain:STRyperErrorDomain code:NSManagedObjectValidationError userInfo:userInfo];
	
}



+(instancetype)fileReadErrorWithFileName:(NSString *)fileName Errors:(NSArray <NSError *> *)errors {
	NSString *errorDescription = [NSString stringWithFormat:@"File '%@' could not be imported due to errors.", fileName.lastPathComponent];
	NSString *suggestion = @"Please, check the expected file format in the application user guide.";
	
	NSDictionary *userInfo = @{NSLocalizedDescriptionKey : errorDescription,
							   NSLocalizedRecoverySuggestionErrorKey : suggestion,
							   NSDetailedErrorsKey : errors};
	
	return [self errorWithDomain:STRyperErrorDomain code:NSFileReadUnsupportedSchemeError userInfo:userInfo];
}

@end
