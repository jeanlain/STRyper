//
//  SmartFolder.m
//  STRyper
//
//  Created by Jean Peccoud on 24/11/2022.
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



#import "SmartFolder.h"
#import "Chromatogram.h"
#import "NSPredicate+PredicateAdditions.h"
#import "SampleSearchHelper.h"
#import "SampleFolder.h"


@implementation SmartFolder

@dynamic searchPredicateData;
@synthesize searchPredicate = _searchPredicate, predicatedWithRoundedDates = _predicatedWithRoundedDates;



- (instancetype)initWithParentFolder:(SampleFolder *)parent searchPredicate:(NSPredicate *)searchPredicate {
	self = [super initWithParentFolder:parent];
	if(self) {
		self.searchPredicate = searchPredicate;
	}
	return self;
}


- (BOOL)isSmartFolder {
	return YES;
}


- (BOOL)canTakeSubfolders {
	return NO;
}


- (NSString *)folderType {
	return @"Smart folder";
}


- (Class)parentFolderClass {
	/// smart folders can only be subfolders or SampleFolder instances
	return SampleFolder.class;
}


- (NSPredicate *)searchPredicate {
	return [NSKeyedUnarchiver unarchivedObjectOfClass: [NSPredicate class] fromData:self.searchPredicateData error:nil];
}


- (void)setSearchPredicate:(NSPredicate *)predicate {
	if(predicate) {
		self.searchPredicateData = [NSKeyedArchiver archivedDataWithRootObject:predicate requiringSecureCoding:NO error:nil];
	} else {
		self.searchPredicateData = nil;
	}
}


- (nullable NSSet<Chromatogram *> *)samples {

	NSPredicate *newPredicate = self.predicatedWithRoundedDates;
	if(!newPredicate) {
		return nil;
	}
	SampleSearchHelper *helper = SampleSearchHelper.sharedHelper;
	if(self.managedObjectContext == helper.managedObjectContext) {
		return [helper samplesFoundWithPredicate:newPredicate];
	}
	
	NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:Chromatogram.entity.name];
	request.predicate = newPredicate;
	NSError *error;
	NSArray *samples = [self.managedObjectContext executeFetchRequest:request error:&error];
	if(error) {
		NSLog(@"The fetch request could not be executed.\n%@", error);
	}
	return [NSSet setWithArray:samples];
}


/// for compatibility with the SampleFolder class
- (nullable NSSet<Chromatogram *> *)allSamples {
	return self.samples;
}


+ (NSSet<NSString *> *)keyPathsForValuesAffectingSamples {
	/// if the predicate changes, the found samples must also change.
	/// We return the path of the core data attribute, as it also changes during undo (our searchPredicate property would not)
	return [NSSet setWithObject:@"searchPredicateData"];
}


- (void)refresh {
	[self willChangeValueForKey:@"samples"];
	[self didChangeValueForKey:@"samples"];
}


- (NSPredicate *)predicatedWithRoundedDates {
	return self.searchPredicate.predicateWithFullDayComparisons;
}


+(BOOL)supportsSecureCoding {
	return YES;
}


@end
