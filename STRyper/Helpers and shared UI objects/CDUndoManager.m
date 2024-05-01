//
//  CDUndoManager.m
//  STRyper
//
//  Created by Jean Peccoud on 10/12/2023.
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


#import "CDUndoManager.h"

@implementation CDUndoManager {
	NSString *currentActionName;
}


- (void)setManagedObjectContext:(NSManagedObjectContext *)managedObjectContext {
	
	if(_managedObjectContext) {
		_managedObjectContext = nil;
		[NSNotificationCenter.defaultCenter removeObserver:self];
	}
	if(managedObjectContext.undoManager == self) {
		_managedObjectContext = managedObjectContext;
		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(contextDidChange:)
												   name:NSManagedObjectContextObjectsDidChangeNotification
												 object:managedObjectContext];
	}
}


- (void)setActionName:(NSString *)actionName {
	if(_managedObjectContext) {
		currentActionName = actionName.copy;
	} else {
		[super setActionName:actionName];
	}
}


- (void)forceActionName:(NSString *)actionName {
	[super setActionName:actionName];
}


- (void)contextDidChange:(NSNotification *)notification {
	if(currentActionName.length > 0) {
		[super setActionName:currentActionName];
		currentActionName = nil;
	}
}


- (void)dealloc {
	if(_managedObjectContext) {
		[NSNotificationCenter.defaultCenter removeObserver:self];
	}
}


@end
