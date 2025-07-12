//
//  SampleFolder.m
//  STRyper
//
//  Created by Jean Peccoud on 20/11/12.
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



#import "SampleFolder.h"
#import "Chromatogram.h"
#import "SampleFolder.h"


@implementation SampleFolder

@dynamic samples;

static void *subfoldersChangedContext = &subfoldersChangedContext;

NSNotificationName const SampleFolderSubfoldersDidChangeNotification = @"SampleFolderSubfoldersDidChangeNotification";


- (NSSet<Chromatogram *> *)allSamples {
	
	NSMutableSet *allSamples = self.samples.mutableCopy;
	if(!allSamples) {
		allSamples = NSMutableSet.new;
	}
	for(SampleFolder *folder in self.allSubfolders) {
		if([folder isKindOfClass:SampleFolder.class]) {
			[allSamples unionSet:folder.samples];
		}
	}
	return allSamples.copy;
}



- (void)awakeFromFetch {
	[super awakeFromFetch];
	if(self.managedObjectContext.concurrencyType == NSMainQueueConcurrencyType) {
		
		/// To be able to post the notification of a change in subfolders, we observe our own subfolders.
		/// This may not be the most elegant, but it ensures that all instances can post the notification.
		[self addObserver:self forKeyPath:@"subfolders" options:NSKeyValueObservingOptionNew context:subfoldersChangedContext];
	}
}


- (void)awakeFromInsert {
	[super awakeFromInsert];
	if(self.managedObjectContext.concurrencyType == NSMainQueueConcurrencyType) {
		[self addObserver:self forKeyPath:@"subfolders" options:NSKeyValueObservingOptionNew context:subfoldersChangedContext];
	}
}
	

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if(context == subfoldersChangedContext) {
		[NSNotificationCenter.defaultCenter postNotificationName:SampleFolderSubfoldersDidChangeNotification object:self];
		/// communicating directly with a UI element like FolderListController would be quicker (the notification center may induce a short delay), but much less clean in terms of separation between UI and model
	} else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}


- (void)willTurnIntoFault {
	[super willTurnIntoFault];
	@try {
		[self removeObserver:self forKeyPath:@"subfolders"];
	} @catch (NSException *exception) {
		
	}
}


#pragma mark - archiving/unarchiving

+(BOOL)supportsSecureCoding {
	return YES;
}


- (void)encodeWithCoder:(NSCoder *)coder {
	/// When archiving, we encode our samples and subfolders, hence all our contents are encoded.
	/// Obviously, we don't encode our parent, otherwise the whole database would be archived.
	if(NSProgress.currentProgress.isCancelled) {
		return;
	}
	[super encodeWithCoder:coder];
	[coder encodeObject:self.samples forKey:@"samples"];
	[coder encodeObject:self.subfolders forKey:@"subfolders"];
}


- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	self.subfolders = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSOrderedSet.class, SampleFolder.class, nil] forKey:@"subfolders"];
	self.samples = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSSet.class, Chromatogram.class, nil] forKey:@"samples"];
	if(NSProgress.currentProgress.isCancelled) {
		return nil;
	}
	return self;
}




@end
