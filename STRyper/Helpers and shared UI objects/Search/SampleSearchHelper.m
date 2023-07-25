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
		controller = [[self alloc] init];
	});
	return controller;
}


- (instancetype)init {
	self = [super init];
	if(self) {
		NSManagedObjectContext *MOC = ((AppDelegate *)NSApp.delegate).managedObjectContext;
		if(!MOC) {
			return self;
		}
		
		NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:Chromatogram.entity.name];
		request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"nChannels" ascending:YES]];		/// we don't use sorting (the samples array controller does it for us), but a sort descriptor is required
		fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:request
																	   managedObjectContext:MOC sectionNameKeyPath:nil cacheName:nil];
		fetchedResultsController.delegate = (id)self;
		
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
		_searchWindow.message = @"Find samples meeting the following criteria:";
		[self configurePredicateEditor];
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

/// Configures the predicate editors with Chromatogram keys corresponding to columns shown by the sample table.
- (void)configurePredicateEditor {
	
	if(!self.predicateEditor) {
		return;
	}
	
	/// The searchable attributes are those shown in the sample table.
	NSDictionary *columnDescription = SampleTableController.sharedController.columnDescription;
	/// We also use the column ids to show searchable attributes in a consistent order
	NSArray *sampleColumnIDs = SampleTableController.sharedController.orderedColumnIDs;
	if(!columnDescription || !sampleColumnIDs) {
		return;
	}
	
	NSArray *columnDescriptions = [columnDescription objectsForKeys:sampleColumnIDs notFoundMarker:@""];		/// Dictionaries describing the sample-related columns
	/// we prepare the keyPaths (attributes) that the predicate editor will allow searching. sampleName and folder are not in sampleColumnIDs
	NSArray *keyPaths = @[ChromatogramSampleNameKey, @"folder.name"];
	/// We also prepare the titles for the menu items of the editor left popup buttons, as keypath names are not user-friendly
	NSArray *titles = @[@"Sample Name", @"Folder name"];
	
	for(NSDictionary *colDescription in columnDescriptions) {
		keyPaths = [keyPaths arrayByAddingObject:[colDescription valueForKey:KeyPathToBind]];
		titles = [titles arrayByAddingObject:[colDescription valueForKey:ColumnTitle]];
	}
	
	NSArray *rowTemplates = [NSPredicateEditorRowTemplate templatesWithAttributeKeyPaths:keyPaths inEntityDescription:Chromatogram.entity];
	
	/// for float attributes, we modify the template so that it only shows the < and > operators (equality is not very relevant for floats)
	NSMutableArray *finalTemplates = [NSMutableArray arrayWithArray:rowTemplates];
	for(NSPredicateEditorRowTemplate *template in rowTemplates) {
		if(template.rightExpressionAttributeType == NSFloatAttributeType){
			NSPredicateEditorRowTemplate *replacementTemplate = [[NSPredicateEditorRowTemplate alloc]
																 initWithLeftExpressions:template.leftExpressions
																 rightExpressionAttributeType:NSFloatAttributeType
																 modifier:template.modifier
																 operators:@[@(NSGreaterThanPredicateOperatorType), @(NSLessThanPredicateOperatorType)]
																 options: 0];
			finalTemplates[[rowTemplates indexOfObject:template]] = replacementTemplate;
		}
	}
	
	NSArray *compoundTypes = @[@(NSNotPredicateType), @(NSAndPredicateType),  @(NSOrPredicateType)];
	NSPredicateEditorRowTemplate *compound = [[NSPredicateEditorRowTemplate alloc] initWithCompoundTypes:compoundTypes];
	
	/// The predicate editor has a compound predicate row template created in IB, we keep it
	self.predicateEditor.rowTemplates = [@[compound] arrayByAddingObjectsFromArray:finalTemplates];
	
	
	/// We create a formatting dictionary to translate attribute names into menu item titles. We don't translate other fields (operators)
	NSArray *keys = NSArray.new;		/// the future keys of the dictionary
	for(NSString *keyPath in keyPaths) {
		NSString *key = [NSString stringWithFormat: @"%@%@%@",  @"%[", keyPath, @"]@ %@ %@"];		/// see https://funwithobjc.tumblr.com/post/1482915398/localizing-nspredicateeditor
		keys = [keys arrayByAddingObject:key];
	}
	
	NSArray *values = NSArray.new;	/// the future values
	for(NSString *title in titles) {
		NSString *value = [NSString stringWithFormat: @"%@%@%@",  @"%1$[", title, @"]@ %2$@ %3$@"];
		values = [values arrayByAddingObject:value];
	}
	
	self.predicateEditor.formattingDictionary = [NSDictionary dictionaryWithObjects:values forKeys:keys];
	
}


- (BOOL)beginSheetModalFoWindow:(NSWindow *)window withPredicate:(nullable NSPredicate *)searchPredicate completionHandler:(void (^)(NSModalResponse returnCode))callbackBlock {
	
	SearchWindow *searchWindow = self.searchWindow;
	
	if(!searchWindow || !window.isVisible) {
		NSLog(@"The search sheet could not be shown.");			/// not very informative (TO IMPROVE)
		return NO;
	}
	
	if(!searchPredicate) {
		searchPredicate = [NSPredicate predicateWithFormat: @"(%K CONTAINS[c] '' )", ChromatogramSampleNameKey];
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


- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

@end
