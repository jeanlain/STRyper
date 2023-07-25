//
//  PanelFolder.m
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



#import "PanelFolder.h"

@interface PanelFolder()

/// a Panel folder has no markers in the model, but we implement this property to return nil.
/// We do it because a tableview's content is bound to the markers property of the selected item (PanelFolder or Panel)
@property (readonly, nonatomic) NSSet *markers;


@end


@implementation PanelFolder

static void *subfoldersChangedContext = &subfoldersChangedContext;
NSNotificationName const PanelFolderSubfoldersDidChangeNotification = @"PanelFolderSubfoldersDidChangeNotification";



- (void)awakeFromFetch {
	[super awakeFromFetch];
	[self addObserver:self forKeyPath:@"subfolders" options:NSKeyValueObservingOptionNew context:subfoldersChangedContext];
}


- (void)awakeFromInsert {
	[super awakeFromInsert];
	[self addObserver:self forKeyPath:@"subfolders" options:NSKeyValueObservingOptionNew context:subfoldersChangedContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if(context == subfoldersChangedContext) {
		[NSNotificationCenter.defaultCenter postNotificationName:PanelFolderSubfoldersDidChangeNotification object:self];
	} else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}



- (NSSet *)markers {
	return nil;
}

+(BOOL)supportsSecureCoding {
	return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
	/// If a Folder Panel is encoded when a sample folder is archived, it means that the samples have at least one panel within a folder.
	/// So we encode our parent folder to preserve the original hierarchy up to the root. We do not encode the subfolders, which may contain irrelevant panels
	[super encodeWithCoder:coder];
	if(self.parent.parent) {
		/// we do not encode the root folder (which has no parent and is invisible to the user)
		[coder encodeObject:self.parent forKey:@"parent"];
	}
}


- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if(self) {
		self.parent = [coder decodeObjectOfClass:PanelFolder.class forKey:@"parent"];
	}
	return self;
}

@end
