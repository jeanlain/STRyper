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


@interface Allele ()

/// The attribute corresponding to the``LadderFragment/additional`` property, as defined in the managed object model.
///
/// It was written in a typo which I didn't want to shown in the public header.
/// I didn't want to create a new model version just to correct the typo either.
@property (nonatomic) BOOL additionnal;

@end

@interface Allele (DynamicAccessors)
/// to set attributes and relationships that are readonly in the interface file

-(void)managedObjectOriginal_setGenotype:(Genotype *)genotype;
-(void)managedObjectOriginal_setAdditionnal:(BOOL)additional;
-(BOOL)managedObjectOriginal_additionnal;

@end


@interface Allele ()

/// The allele size as it can be shown in a table. This allows returning `nil` if the allele has a scan of 0 (to avoid showing a size of 0).
@property (nonatomic, readonly) NSNumber *visibleSize;

/// Convenience property used to show additional fragments of a genotype in a table.
@property (nonatomic, readonly) NSString *sizeAndName;


@end


@implementation Allele
@dynamic genotype, additionnal, size;

- (nullable instancetype)initWithGenotype:(Genotype *)genotype additional:(BOOL)additional {
	if(!genotype.managedObjectContext) {
		return nil;
	}
	Mmarker *marker = genotype.marker;
	Trace *trace = [genotype.sample traceForChannel:marker.channel];
	if(!trace) {
		return nil;
	}
	NSInteger ploidy = marker.ploidy;
	if(!additional && genotype.alleles.count > ploidy && genotype.assignedAlleles.count >= ploidy) {
		return nil;
	}  
	self = [super initWithContext:genotype.managedObjectContext];
	if (self) {
		[self managedObjectOriginal_setAdditionnal:additional];
		[self managedObjectOriginal_setGenotype:genotype];
		[self managedObjectOriginal_setTrace:trace];
	}
	return self;
}

static NSArray<NSString *> *observedAttributes;
static void *attributeChangeContext = &attributeChangeContext;

+ (void)initialize {
	if (self == [Allele class]) {
		observedAttributes = @[@"genotype", @"size", @"name", @"scan"];
	}
}

- (void)awakeFromFetch {
	[super awakeFromFetch];
	if(self.managedObjectContext.concurrencyType == NSMainQueueConcurrencyType) {
		[self observeAttributes];
	}
}


- (void)awakeFromInsert {
	[super awakeFromInsert];
	if(self.managedObjectContext.concurrencyType == NSMainQueueConcurrencyType) {
		[self observeAttributes];
	}
}


-(void) observeAttributes {
	for(NSString *attribute in observedAttributes) {
		[self addObserver:self forKeyPath:attribute options:NSKeyValueObservingOptionNew context:attributeChangeContext];
	}
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context == attributeChangeContext) {
		[self.genotype _alleleAttributeDidChange];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}


- (void)willTurnIntoFault {
	[super willTurnIntoFault];
	@try {
		for(NSString *attribute in observedAttributes) {
			[self removeObserver:self forKeyPath:attribute];
		}
	 } @catch (NSException *exception) {
		 // If observer wasn’t added, ignore exception
	 }
}


-(void)findNameFromBins {
	if(self.scan <= 0) {
		return;
	}
	NSSet *bins = self.genotype.marker.bins;
	if(bins.count == 0) {
		/// If there is no bin, we remove the name so that the `string` property returns the size.
		self.name = nil;
		return;
	}
	
	float size = self.size;
	for (Bin *bin in bins) {
		if (size >= bin.start && size <= bin.end) {
			self.name = bin.name;
			return;
		}
	}
	NSString *name = [NSUserDefaults.standardUserDefaults stringForKey:DubiousAlleleName];
	if(!name) {
		name = @"?";
	}
	self.name = name;

}


- (void)setScan:(int32_t)scan {
	[self managedObjectOriginal_setScan:scan];
	if(self.scan <= 0 && !self.additional) {
		/// an allele that is missing (no peak found) has a scan of zero, but is still present
		self.name = [NSUserDefaults.standardUserDefaults stringForKey:MissingAlleleName];
	}
	/// if the scan has changed, the size must be updated
	[self computeSize];
}


- (BOOL)additional {
	return [self managedObjectOriginal_additionnal];
}


-(void) computeSize {
	if(self.scan <= 0) {
		/// an allele that is missing (no peak found) has a scan of zero, but is still present
		self.size = -1000;
	} else {
		Chromatogram *sample = self.trace.chromatogram;
		if(sample) {
			if(sample.sizingQuality.floatValue <= 0) {
				self.size = -1000;
				return;
			}
			float size = [sample sizeForScan:self.scan];
			if(self.genotype.offsetData) {
				MarkerOffset offset = self.genotype.offset;
				self.size = (size - offset.intercept)/offset.slope;
			} else {
				self.size = size;
			}
		}
	}
}



- (NSString *)string {
	if(self.name.length > 0) {
		return self.name;
	}
	return super.string;
}

/// Convenience method used to show additional fragments of a genotype in a table.
- (NSString *)sizeAndName {
	if(self.name.length > 0) {
		return [super.string stringByAppendingFormat:@":%@", self.name];
	}
	return super.string;
}


+ (NSSet<NSString *> *)keyPathsForValuesAffectingVisibleSize:(NSString *)key {
	return [NSSet setWithObject:@"size"];
}


+ (NSSet<NSString *> *)keyPathsForValuesAffectingSizeAndName:(NSString *)key {
	return [NSSet setWithObjects:@"size", @"name", nil];
}


- (NSNumber *)visibleSize {
	if(self.scan == 0 || self.size <= -1000.0) {
		return nil;
	}
	return @(self.size);
}


- (void)removeFromGenotypeAndDelete {
	if(self.additional) {
		self.name = nil;
		[self managedObjectOriginal_setGenotype:nil];
		[self managedObjectOriginal_setTrace:nil];
		[self.managedObjectContext deleteObject:self];
	}
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
