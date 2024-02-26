//
//  NSManagedObjectContext+NSManagedObjectContextAdditions.m
//  STRyper
//
//  Created by Jean Peccoud on 08/02/2023.
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



#import "NSManagedObjectContext+NSManagedObjectContextAdditions.h"

@implementation NSManagedObjectContext (NSManagedObjectContextAdditions)

- (nullable __kindof NSManagedObject *)objectForURIString:(NSString *)URIString expectedClass:(Class)class {
	if(URIString) {
		NSURL *URI = [NSURL URLWithString:URIString];
		if([URI.scheme isEqualToString:@"x-coredata"]) {
			/// We use this check otherwise the method below throws an exception and causes app malfunction.
			NSManagedObjectID *ID = [self.persistentStoreCoordinator managedObjectIDForURIRepresentation:URI];
			if(ID) {
				NSError *error;
				NSManagedObject *object = [self existingObjectWithID:ID error:&error];
				
				if(!error) {
					if(!class || [object isKindOfClass:class]) {
						return object;
					}
				}
			}
		} else {
			NSLog(@"invalid URI: %@", URIString);
		}
	}
	return nil;
}


-(BOOL)trySavingWithUndo {
	NSUndoManager *undoManager = self.undoManager;
	while(undoManager.canUndo) {
		[undoManager undo];
		if(self.hasChanges) {
			if([self save:nil]) {
				return YES;
			}
		} else {
			return YES;
		}
	}
	
	if(self.hasChanges) {
		[self rollback];
	}
	return NO;
}

@end
