//
//  SizeStandard.m
//  STRyper
//
//  Created by Jean Peccoud on 21/12/12.
//  Copyright (c) 2012 Jean Peccoud. All rights reserved.
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



#import "SizeStandard.h"
#import "SizeStandardSize.h"
#import "PeakLabel.h"
#import "LadderFragment.h"
#import "FragmentLabel.h"
#import "Chromatogram.h"
#import "Trace.h"
#import "TraceView.h"
@import Accelerate;


@interface SizeStandard (DynamicAccessors)

-(void)managedObjectOriginal_setName:(NSString *)name;

@end

@interface SizeStandard ()

@property (nonatomic, readonly) NSString* tooltip;	/// a string used to bind to a tooltip of an image view (padlock) in the size standard table, telling that the size standard cannot be modified.
													/// this solution is a bit lazy. It would be better to separate the model form the UI

@end

NSString * const SizeStandardNameKey = @"name";

@implementation SizeStandard



@dynamic editable, name, sizes, samples;

- (void)autoName {
	NSString *candidateName = self.name;
	NSArray *siblings = [self siblings];

	int i = 1;
	BOOL ok = NO;
	while(!ok) {
		NSString *suffix = [NSString stringWithFormat:@" %d",i];
		if(i == 1) {
			suffix = @"";
		}
		candidateName =[NSString stringWithFormat:@"%@ -copy%@", self.name, suffix];
		NSArray *existingStandards = [siblings filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == %@", candidateName]];
		if(existingStandards.count == 0) ok = YES;
		i++;
	}
	self.name = candidateName;

}

- (NSArray *)siblings {
	NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:self.entity.name];
	NSArray *siblings = [self.managedObjectContext executeFetchRequest:request error:nil];
	NSMutableArray *temp = [NSMutableArray arrayWithArray:siblings];
	if(temp.count) {
		[temp removeObject:self];
	}
	return [NSArray arrayWithArray:temp];
}

- (NSString *)tooltip {
	return self.editable? @"": @"This size standard cannot be modified";
}



- (void)setName:(NSString *)name {		// overridden just to specify the undo menu title
	[self managedObjectOriginal_setName:name];
	if(!self.deleted) {
		[self.managedObjectContext.undoManager setActionName: @"Rename Size Standard"];
	}
}


- (BOOL)validateName:(id  _Nullable __autoreleasing *) value error:(NSError *__autoreleasing  _Nullable *)error {		/// raises an error if several standards have the same name
    NSString *name = *value;
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:SizeStandard.entity.name];
    NSArray *standards = [self.managedObjectContext executeFetchRequest:request error:nil];
    if(standards) {
        for (SizeStandard *standard in standards) {
            if(standard != self && [name isEqualToString:standard.name]) {
				if (error != NULL) {
					NSString *reason = [NSString stringWithFormat:@"Duplicate size standard name ('%@')", name];
					*error = [NSError managedObjectValidationErrorWithDescription:[NSString stringWithFormat:@"A size standard named '%@' already exists", name]
																	   suggestion:@"Please, use another name."
																		   object:self reason:reason];
				}
                return NO;
            }
        }
    }
   
    return YES;
}


- (BOOL)validateFragments:(id _Nullable __autoreleasing *)valueRef error:(NSError * _Nullable __autoreleasing *)error {
	NSSet *fragments = *valueRef;
	if(fragments.count < 4) {
		if (error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"Size standard '%@' has less than 4 sizes.", self.name];
			*error = [NSError managedObjectValidationErrorWithDescription:reason
															   suggestion:@"Add sizes to this size standard."
																   object:self
																   reason:reason];
		}
		return NO;
	}
	return YES;
}



#pragma mark - archiving/unarchiving

+(BOOL)supportsSecureCoding {
	return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
	[super encodeWithCoder:coder];
	[coder encodeObject:self.sizes forKey:@"sizes"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if(self) {
		self.sizes = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSSet.class, SizeStandardSize.class, nil]  forKey:@"sizes"];
		self.editable = YES;				/// standards imported from folder archives are always editable. Non-editable standards should not be imported anyway (see below), since they are already in the database
	}
	return self;
}


- (BOOL)isEquivalentTo:(__kindof NSManagedObject *)obj {
	if(obj.class != self.class) {
		return NO;
	}
	SizeStandard *standard = obj;
	if(standard.sizes.count != self.sizes.count) {
		return NO;
	}
	NSSet *sizes = [self.sizes valueForKeyPath:@"@distinctUnionOfObjects.size"];		/// equivalence in only based on the sizes of the fragments. We don't check for names.
	NSSet *objSizes = [standard.sizes valueForKeyPath:@"@distinctUnionOfObjects.size"];
	
	if([sizes isEqualToSet: objSizes]) {
		return YES;
	}
	return NO;
}


@end
