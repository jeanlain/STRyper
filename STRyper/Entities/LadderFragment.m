//
//  LadderFragment.m
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



#import "LadderFragment.h"
#import "Chromatogram.h"
#import "FragmentLabel.h"

CodingObjectKey LadderFragmentScanKey = @"scan",
LadderFragmentSizeKey = @"size",
LadderFragmentNameKey = @"name",
LadderFragmentStringKey = @"string",
LadderFragmentOffsetKey = @"offset";


@implementation LadderFragment

@dynamic scan, size, trace, offset, name;

- (void)setTrace:(Trace*)trace {
	/// a ladder fragment without a trace should be deleted
	BOOL shouldDelete = self.trace != nil && trace == nil && !self.deleted;
	[self managedObjectOriginal_setTrace:trace];
	if(shouldDelete) {
		[self.managedObjectContext deleteObject:self];
	}
}


+ (NSSet<NSString *> *)keyPathsForValuesAffectingString {
	return [NSSet setWithObjects:@"size", @"name", nil];
}


- (NSString *)string {
	
	float size = self.size;
	if(size == roundf(size)) { 				/// if its size is integer (typical for ladder fragment), we show it as is
		return [NSString stringWithFormat:@"%.f", size];
	} else {								/// else we round it to the nearest decimal
		return [NSString stringWithFormat:@"%.01f", size];
	}
	
	return @"";
}

@end
