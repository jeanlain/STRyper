//
//  Allele.m
//  STRyper
//
//  Created by Jean Peccoud on 28/03/2022.
//  Copyright © 2022 Jean Peccoud. All rights reserved.
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



#import "Allele.h"
#import "Bin.h"
#import "Genotype.h"
#import "Chromatogram.h"
#import "Mmarker.h"


@interface Allele (DynamicAccessors)
/// to set attributes and relationships that are readonly in the interface file

-(void)managedObjectOriginal_setGenotype:(Genotype *)genotype;
-(void)managedObjectOriginal_setName:(NSString *)name;

@end


@interface Allele ()

/// The allele size as it can be shown in a table. This allows returning nil if the allele has a scan of 0 (to avoid showing a size of 0).
@property (nonatomic, readonly) NSNumber *visibleSize;

@end


@implementation Allele
@dynamic genotype;

/// pointers use for context of KVO
static void * const sizeChangedContext = (void*)&sizeChangedContext;
static void * const nameChangedContext = (void*)&nameChangedContext;


- (void)awakeFromFetch {
	[super awakeFromFetch];
	/// We observe some of our one attributes to notify the genotype of changes
	/// Observing self is not very elegant but that facilitates undo support as these attributes are reverted during undo
	[self addObserver:self forKeyPath:@"size" options:NSKeyValueObservingOptionNew context:sizeChangedContext];

}


- (void)awakeFromInsert {
	[super awakeFromInsert];
	[self addObserver:self forKeyPath:@"size" options:NSKeyValueObservingOptionNew context:sizeChangedContext];
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if(context == sizeChangedContext) {
		/// if our size changes, the genotypes must assign alleles (see Genotype implementation)
		[self.genotype _assignAlleles];
	}  else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}


- (nullable instancetype)initWithGenotype:(Genotype *)genotype {
	if(!genotype.managedObjectContext) {
		return nil;
	}
	Trace *trace = [genotype.sample traceForChannel:genotype.marker.channel];
	if(!trace) {
		return nil;
	}
	if(genotype.alleles.count >= genotype.marker.ploidy) {
		return nil;
	}  
	self = [super initWithContext:genotype.managedObjectContext];
	if (self) {
		[self managedObjectOriginal_setGenotype:genotype];
		[self managedObjectOriginal_setTrace:trace];
	}
	return self;
}


- (void)setName:(NSString *)name {
	[self managedObjectOriginal_setName:name];
	if(!self.deleted) {
		/// Setting the undo action name is convenient when the user edits the allele name manually,
		/// but this can be costly if many alleles names are changed
		/// perhaps we should move this elsewhere
		[self.managedObjectContext.undoManager setActionName:@"Rename Allele"];
	}
}



-(void)findNameFromBins {
	float size = self.size;
	for (Bin *bin in self.genotype.marker.bins) {
		if (size >= bin.start && size <= bin.end) {
			[self managedObjectOriginal_setName: bin.name];
			return;
		}
	}
	NSString *name = [NSUserDefaults.standardUserDefaults stringForKey:DubiousAlleleName];
	if(!name) {
		name = @"?";
	}
	[self managedObjectOriginal_setName: name];

}


- (void)setScan:(int32_t)scan {
	[self managedObjectOriginal_setScan:scan];
	if(self.scan <= 0) {
		/// an allele that is missing (no peak found) has a scan of zero, but is still present
		[self managedObjectOriginal_setName: [NSUserDefaults.standardUserDefaults stringForKey:MissingAlleleName]];
	}
	/// if the scan has changed, the size must be updated
	[self setSize];
}


-(void) setSize {
	if(self.scan <= 0) {
		/// an allele that is missing (no peak found) has a scan of zero, but is still present
		self.size = 0;
	} else {
		Chromatogram *sample = self.trace.chromatogram;
		if(sample) {
			float size = [sample sizeForScan:self.scan];
			if(self.genotype.offsetData) {
				MarkerOffset offset = self.genotype.offset;
				self.size = size * offset.slope + offset.intercept;
			} else {
				self.size = size;
			}
		}
	}
}



- (NSString *)string {
	if(self.name.length >0) {
		return self.name;
	}
	return super.string;
}


+ (NSSet<NSString *> *)keyPathsForValuesAffectingVisibleSize:(NSString *)key {
	return [NSSet setWithObject:@"size"];
}


- (NSNumber *)visibleSize {
	if(self.scan == 0) {
		return nil;
	}
	return @(self.size);
}


- (BOOL)validateTrace:(id  _Nullable __autoreleasing *) value error:(NSError *__autoreleasing  _Nullable *)error {
	/// we cannot validate our trace if the panel doesn't include our marker
	Trace *trace = *value;
	if(trace.channel != self.genotype.marker.channel) {
		if (error != NULL) {
			*error = [NSError errorWithDescription:[NSString stringWithFormat:@"The allele's trace (sample '%@') and marker '%@' have different channels!", self.trace.chromatogram.sampleName, self.genotype.marker.name]
											suggestion:@""];
		}
		return NO;
	}
	return YES;
}



@end
