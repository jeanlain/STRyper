//
//  Folder.m
//  STRyper
//
//  Created by Jean Peccoud on 23/06/2022.
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



#import "Folder.h"
#import "PanelFolder.h"
#import "FolderListController.h"

@interface Folder ()

- (NSArray *) baseFolders;		/// returns the folders at the root level. Used to identify our siblings if we have no parent

@end


@interface Folder (DynamicAccessors)

-(void)managedObjectOriginal_setName:(nullable NSString *)name;
-(void)managedObjectOriginal_setParent:(nullable Folder *)parent;

@end


@implementation Folder



@synthesize folderType;
@dynamic parent, subfolders, name;



- (instancetype)initWithParentFolder:(Folder *)parent {
	if(!parent.managedObjectContext || parent.class != self.parentFolderClass) {
		return nil;
	}
	self = [super initWithContext:parent.managedObjectContext];
	if(self) {
		[parent addSubfoldersObject:self];
		[self autoName];
	}
	return self;
}


- (Class)parentFolderClass {
	return self.class;
}


- (NSString *)folderType {
	return @"Folder";
}


- (BOOL) isAncestorOf:(Folder*)folder {
	if (folder == self) return YES;
	while (folder.parent) {
		if (folder.parent == self)
			return YES;
		else folder = folder.parent;
	}
	return NO;
}


- (BOOL)isPanel {
	return NO;
}


- (BOOL)isSmartFolder {
	return NO;
}

- (BOOL)canTakeSubfolders {
	return YES;
}


- (void)setName:(NSString *)name {
	[self managedObjectOriginal_setName:name];
	if(!self.deleted) {
		[self.managedObjectContext.undoManager setActionName: [@"Rename " stringByAppendingString: self.folderType]];
	}
}


- (NSSet <Folder *>*)allSubfolders {
	if(!self.subfolders) {
		return NSSet.new;
	}
	NSMutableSet *subfolders = [NSMutableSet setWithSet:self.subfolders.set];
	for(Folder *folder in self.subfolders) {
		[subfolders unionSet:[folder allSubfolders]];
	}
	return [NSSet setWithSet:subfolders];
}


- (Folder *)topAncestor {
	Folder *parent = self.parent;
	if(!parent) {
		return self;
	}
	while(parent.parent) {
		parent = parent.parent;
	}
	return parent;
}


-(NSArray<Folder *> *)ancestors {
	NSArray *ancestors = NSArray.new;
	Folder *parent = self.parent;
	while(parent) {
		ancestors = [ancestors arrayByAddingObject:parent];
		parent = parent.parent;
	}
	return ancestors;
}


- (void)setParent:(Folder *)parent {
	[self managedObjectOriginal_setParent:parent];
	if(!self.name) {
		[self autoName];
	}
}


- (NSArray *) baseFolders {		// returns the folders at the root level
	NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:self.entity.name];
	NSArray *folders = [self.managedObjectContext executeFetchRequest:request error:nil];
	if(!folders) return NSArray.new;
	return [folders filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"parent == nil"]];

}

- (NSArray *) siblings {
	if(!self.parent) {
		return NSArray.new;
	}
	NSMutableArray *siblings = [NSMutableArray arrayWithArray: self.parent.subfolders.array];
	[siblings removeObject:self];
	return [siblings filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"folderType == %@", self.folderType]];
}
  

- (void)autoName {
	NSArray *siblings = self.siblings;
	NSString *prefix = [@"Unnamed " stringByAppendingString: self.folderType];
	if(self.isSmartFolder) {
		prefix = @"Search Results";
	}
	if(self.name) {
		prefix = self.name;
	}
	NSString *candidateName = prefix;
	if (siblings.count) {
		int i = 1;
		BOOL ok = NO;
		do {
			NSString *suffix = [NSString stringWithFormat:@" %d", i];
			if(i == 1) {
				suffix = @"";
			}
			candidateName = [prefix stringByAppendingString: suffix];
			for (Folder *folder in siblings) {
				if([candidateName isEqualToString:folder.name]) {
					ok = NO;
					break;
				} else ok = YES;
			}
			i++;
		} while(!ok);
	}
	self.name = candidateName;
}



- (BOOL)validateName:(id  _Nullable __autoreleasing *) value error:(NSError *__autoreleasing  _Nullable *)error {
	NSString *name = *value;
	
	if(name.length == 0) {
		if (error != NULL) {
			NSString *description = [NSString stringWithFormat:@"The %@ must have a name.", self.folderType.lowercaseString];
			*error = [NSError managedObjectValidationErrorWithDescription:description
															   suggestion:@""
																   object:self
																   reason:description];

		}
		return NO;
	}
	
	NSArray *folders = self.siblings;
	if(folders) {
		for (Folder *folder in folders) {
			if(folder != self && [name isEqualToString:folder.name] && folder.class == self.class) {
				if (error != NULL) {
					NSString *description = [NSString stringWithFormat:@"A %@ with the same name is already present at this location", self.folderType];
					NSString *reason = [NSString stringWithFormat:@"Duplicate folder name ('%@') for folders of the same parent.", name];
					*error = [NSError managedObjectValidationErrorWithDescription:description suggestion:@"Please, use another name." object:self reason:reason];
				}
				return NO;
			}
		}
	}
	return YES;
}


- (BOOL)validateParent:(id _Nullable __autoreleasing *)value error:(NSError * _Nullable __autoreleasing *)error {
	Folder *parent = *value;
	if(parent == self.parent) {		/// I'm not sure why, but sometimes the validation is sent when the parent hasn't changed
		return YES;
	}
	
	if(parent && parent.class != self.parentFolderClass) {	/// this prevents panels from being put in sample folders, samples/smart folders into panel folders, etc. Panels and smart folders cannot take subfolders.
		if (error != NULL) {
			/// the error wouldn't help the user much. in principle, this situation should never happen.
			NSString *description = [NSString stringWithFormat:@"The parent %@ cannot contain this %@ because the folder types are incompatible", parent.folderType, self.folderType];
			NSString *reason = [NSString stringWithFormat:@"Parent class: %@, folder class: %@", parent.className, self.className];
			*error = [NSError managedObjectValidationErrorWithDescription:description suggestion:@"" object:self reason:reason];
		}
		return NO;
	}
	NSArray *folders;
	if(parent) {
		folders = parent.subfolders.array;
	} else {
		folders = [self baseFolders];
	}
	for (Folder *folder in folders) {
		if(folder != self && [self.name isEqualToString:folder.name] && folder.class == self.class) {
			if (error != NULL) {
				NSString *description = [NSString stringWithFormat:@"A %@ with the same name is already present at this location", self.folderType];
				NSString *reason = [NSString stringWithFormat:@"Duplicate folder name %@ in the same parent.", self.name];
				*error = [NSError managedObjectValidationErrorWithDescription:description suggestion:@"Choose a different name." object:self reason:reason];
			}
			return NO;
		}
	}
	return YES;
}


@end
