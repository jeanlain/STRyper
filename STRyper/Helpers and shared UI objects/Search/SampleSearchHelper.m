//
//  SampleSearchHelper.m
//  STRyper
//
//  Created by Jean Peccoud on 07/12/2022.
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



#import "SampleSearchHelper.h"
#import "SampleTableController.h"
#import "FolderListController.h"
#import "SmartFolder.h"
#import "Chromatogram.h"
#import "AppDelegate.h"
#import "SearchWindow.h"



@implementation SampleSearchHelper {
	
	/// The object doing sample fetch, whose fetch predicate is specified by the selected smart folder.
	///
	/// We don't use it to populate any tableview, since the sample table shows the content of regular folders, which don't need a fetch request. (And NSFetchedResultsController seems tailored to iOS anyway)
	/// We only use one of its delegate methods to dynamically update the search results.
	NSFetchedResultsController *fetchedResultsController;
	
	/// Tells if the view context has been saved since the last fetch. We use it determine whether we should refresh the search.
	///
	/// Search results may be affected by changes that are not detected by the fetchedResultsController,
	/// when they don't directly affect chromatogram attributes, but some attributes of related object, like the name of the parent folder, panel, or size standard
	/// But the new results can only be obtained after such change was save. So we use this bool to determine whether we should do a fetch.
	BOOL didSaveSinceLastSearch;

}


@synthesize searchWindow = _searchWindow;

+ (instancetype)sharedHelper {
	static SampleSearchHelper *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = self.new;
	});
	return controller;
}


- (instancetype)init {
	self = [super init];
	if(self) {
		NSManagedObjectContext *MOC = AppDelegate.sharedInstance.managedObjectContext;
		if(!MOC) {
			return self;
		}
		
		NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:Chromatogram.entity.name];
		request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"nChannels" ascending:YES]];		/// we don't use sorting (the samples array controller does it for us), but a sort descriptor is required
		fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:request
																	   managedObjectContext:MOC sectionNameKeyPath:nil cacheName:nil];
		fetchedResultsController.delegate = self;
		
		/// we react when the view context saves, to potentially fetch samples.
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(contextDidSave)
													 name:NSManagedObjectContextDidSaveNotification
												   object:MOC];


	}
	return self;
}

# pragma mark - managing the search window

- (SearchWindow *)searchWindow {
	if(!_searchWindow) {
		_searchWindow = SearchWindow.searchWindow;
		_searchWindow.message = @"Find samples meeting the following conditions:";
		[SampleTableController.sharedController configurePredicateEditor:self.predicateEditor];

	}
	return _searchWindow;
}


- (NSPredicate *)predicate {
	return self.searchWindow.predicate;
}


- (void)setPredicate:(NSPredicate *)predicate {
	self.searchWindow.predicate = predicate;
}


- (NSPredicateEditor *)predicateEditor {
	return self.searchWindow.predicateEditor;
}


- (BOOL)beginSheetModalFoWindow:(NSWindow *)window withPredicate:(nullable NSPredicate *)searchPredicate completionHandler:(void (^)(NSModalResponse returnCode))callbackBlock {
	
	SearchWindow *searchWindow = self.searchWindow;
	
	if(!searchWindow || !window.isVisible) {
		NSLog(@"The search sheet could not be shown.");			/// not very informative (TO IMPROVE)
		return NO;
	}
	
	if(!searchPredicate) {
		searchPredicate = SampleTableController.sharedController.defaultFilterPredicate;
	}
	
	if(searchPredicate.class != NSCompoundPredicate.class) {
		/// we make the search predicate a compound predicate to make sure it shows the "all/any/none" option.
		searchPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[searchPredicate]];
	}
	
	searchWindow.predicate = searchPredicate;

	[window beginSheet:searchWindow completionHandler:^(NSModalResponse returnCode) {
		callbackBlock(returnCode);
	}];
	
	return YES;
}


# pragma mark - performing sample search

- (nullable NSSet *)samplesFoundWithPredicate:(NSPredicate *)predicate {
	if(![predicate isEqual:fetchedResultsController.fetchRequest.predicate] || didSaveSinceLastSearch) {
		[fetchedResultsController.fetchRequest setPredicate:predicate];
		NSError *error;
		[fetchedResultsController performFetch:&error];
		didSaveSinceLastSearch = NO;
		if(error) {
			[NSApp presentError:error];
			return nil;
		}
	}
	
	NSArray *fetchedObjects = fetchedResultsController.fetchedObjects;
	
	/// We filter results to remove samples that may be in the trash
	SampleFolder *trashFolder = FolderListController.sharedController.trashFolder;
	if(trashFolder.subfolders.count > 0 || trashFolder.samples.count > 0) {
		fetchedObjects = [fetchedObjects filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
			return [evaluatedObject topAncestor] != trashFolder;
		}]];
	}
	return [NSSet setWithArray:fetchedObjects];
}


- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
	/// A change related to Chromatogram objects causes the fetched objects to change. We need to update sample table if a smart folder is selected
	SampleFolder *folder = FolderListController.sharedController.selectedFolder;
	if(folder.isSmartFolder) {
		/// we assume that the objects were fetched according to the criteria defined by the smart folder (the user having selected this folder should ensure that).
		/// Hence we don't do a fetch, and just set the updated contents
		[(SmartFolder *)folder refresh];
	}
}


-(void)contextDidSave {
	didSaveSinceLastSearch = YES;
	SampleFolder *folder = FolderListController.sharedController.selectedFolder;
	if(folder.isSmartFolder) {
		[(SmartFolder *)folder refresh];
	}
}


- (NSManagedObjectContext *)managedObjectContext {
	return fetchedResultsController.managedObjectContext;
}


# pragma mark - validation of editor

+ (nullable NSError *)errorInFieldsOfEditor:(NSView *)editor {
	/// I haven't found a better way to validate text fields of an `NSPredicateEditor` (which is the delegate of its text fields).
	/// Subclassing the `NSPredicateEditor` would not have made things easier, and I don't want validation to be performed each time
	/// a field is edited (using for instance `controlTextDidEnEditing:`).
	NSArray *subViews = [self allSubviewsOf:editor];
	for(NSTextField *textField in subViews) {
		if([textField isKindOfClass:NSTextField.class] && textField.isEditable) {
			NSString *string = textField.stringValue;
			if(string.length == 0) {
				return [NSError errorWithDescription:@"At least one field is empty." suggestion:@"Please, fill all fields."];
			}
			if([textField.formatter isKindOfClass:NSNumberFormatter.class]) {
				NSNumberFormatter *formatter = textField.formatter;
				if([formatter numberFromString:string] == nil) {
					/// In practice, the formatter may have emptied the text field if the string was incorrect before this method is called;
					NSString *description = [NSString stringWithFormat:@"'%@' is not recognized as a number.", string];
					return [NSError errorWithDescription:description suggestion:@"Please, specify a number."];
				}
			}
		}
	}
	
	return nil;
}


/// Returns all subviews of a view, recursively.
/// - Parameter view: a view.
+ (NSArray *)allSubviewsOf:(NSView *)view {
	/// We could have made this a category of `NSView`, but this method is only used here.
	NSMutableArray *allSubviews = [NSMutableArray arrayWithObject:view];
	NSArray *subviews = view.subviews;
	for (NSView *view in subviews) {
		[allSubviews addObjectsFromArray:[self allSubviewsOf:view]];
	}
	return allSubviews;
}


- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

@end
