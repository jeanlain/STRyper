//
//  SampleInspectorController.m
//  STRyper
//
//  Created by Jean Peccoud on 12/11/2022.
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



#import "SampleInspectorController.h"
#import "SampleTableController.h"
#import "SizeStandardTableController.h"
#import "Chromatogram.h"
#import "FittingView.h"
#import "MainWindowController.h"

static NSArray *outlineViewSections, *sampleKeyPaths; /// see +initialize

@interface SampleInspectorController () {
	
	__weak IBOutlet NSOutlineView *outlineView;  /// The outline view that constitute the sample inspector (designed in a nib).
												 /// The singleton object is is the datasource and delegate of the outline view.
	
	NSArrayController *sampleController;		/// This controller facilitates binding with the samples of which we show information.
															  
}

/// The different peak thresholds the user can define for a ladder trace. We use this property to bind to the an NSPopupButton menu contents.
@property (nonatomic) NSArray<NSNumber *> *peakThreshold;
															
@end


@implementation SampleInspectorController

/// Implementation details:
/// The outline view (of which we are the delegate and datasource) has rows that are entirely designed in the nib file loaded in -init.
/// So to understand the implementation, one should inspect the nib file.

+(void)initialize {
	/// the main section titles
	outlineViewSections = @[
		@"Sample information",
		@"Run information",
		@"Sizing",
	];
	

	/// the Chromatogram attribute names that we bind to value of NSTextfields that the inspector tab shows
	sampleKeyPaths = Chromatogram.entity.attributeKeys;
	sampleKeyPaths = [sampleKeyPaths arrayByAddingObjectsFromArray:@[@"dye1", @"dye2",@"dye3", @"dye4", @"dye5"]];
}


+ (instancetype)sharedController {
	static SampleInspectorController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
			controller = [[self alloc] init];
	});
	return controller;
}


- (instancetype)init {
	self = [super initWithNibName:@"SampleInspector" bundle:nil];
	if(self) {
		_peakThreshold = @[@10, @50, @100, @200, @500];
		sampleController = NSArrayController.new;
	}
	return self;
}


- (void)viewDidLoad {
    [super viewDidLoad];

	outlineView.autosaveExpandedItems = YES;
	outlineView.autosaveTableColumns = YES;
	outlineView.autosaveName = @"sampleInspector";
}


- (void)setSamples:(NSArray<Chromatogram *> *)samples {
	sampleController.content = samples;
	/// We use the -selection property of the sampleController for binding keys of chromatogram objects to UI items in the outline view.
	/// This offers more binding options than the -content key.
	/// Hence we select all the items of the controller. Maybe there is a better solution.
	[sampleController setSelectedObjects:samples];
}


- (NSArray<Chromatogram *> *)samples {
	return sampleController.arrangedObjects;
}


#pragma mark - Delegate and datasource methods for the tableview


- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
	NSInteger count = 0;
	if(item == nil) {
		/// the number of main (expandable) sections
		count = outlineViewSections.count;
	} else if([item isKindOfClass:NSString.class]) { /// each section is represented by a string. It has one child (the section's content)
		count = 1;
	}
	return count;
}



-(id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
	if(item == nil) {
		if(index >= 0 && index < outlineViewSections.count) {
			/// the item representing a main section is simply its title as an NSString
			return outlineViewSections[index];
		}
		return NSNull.null;		/// This should never happen, but we cannot return nil (apparently)
	}
	/// For the child (section content), we return an array that contains the section title
	/// This allow differentiating the main sections (NSString objects) from their content (NSArray objects)
	return @[item];
	
}


- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
	return ([item isKindOfClass:NSString.class]);
}


- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
	/// no row is selectable
	return NO;
}


- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
	return item;
}


- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
	if([item isKindOfClass:NSString.class]) {
		/// each main section is represented by a cell view that shows its title
		NSTableCellView *view = [outlineView makeViewWithIdentifier:@"Section" owner:self];
		if(view.textField) {
			/// we add a colon to the section title (because we also use it in identifiers, and Xcode doesn't want colons in identifiers).
			view.textField.stringValue = [item stringByAppendingString:@":"];
		}
		return view;
	}
	/// the content of each section (child) is a row view that has no cell view (but other views set in IB)
	return nil;
}



- (NSTableRowView *)outlineView:(NSOutlineView *)outlineView rowViewForItem:(id)item {
	if([item isKindOfClass:NSArray.class]) {	/// we provide the row view for the child of a main section
												/// the row views have the section titles as identifiers set in IB
												/// they are placed within the outline view in the xib file

		NSTableRowView *rowView = [outlineView makeViewWithIdentifier:[item firstObject] owner:self];
		for(NSView *subView in rowView.subviews) {
			if([subView isKindOfClass:NSTextField.class]) {
				/// a row view contains text fields whose identifiers are attribute names of the Chromatogram entity, to simplify bindings
				if([sampleKeyPaths containsObject:subView.identifier]) {
					NSString *keyPath = [@"selection." stringByAppendingString:subView.identifier];
					if(((NSTextField *)subView).drawsBackground) {
						/// these textfields are those that show dye names.
						[subView bind:NSValueBinding toObject:sampleController
						  withKeyPath:keyPath options:@{NSNoSelectionPlaceholderBindingOption: @"", NSMultipleValuesPlaceholderBindingOption: @"…"}];
						/// Since they draw their background, it is better to hide them when the selected samples don't have the corresponding dye
						[subView bind:NSHiddenBinding toObject:sampleController
						  withKeyPath:keyPath options:@{NSValueTransformerNameBindingOption: NSIsNilTransformerName}];
						[subView bind:@"hidden2" toObject:sampleController		/// we also hide them when no sample is selected (the above binding is insufficient)
						  withKeyPath:@"content.@count" options:@{NSValueTransformerNameBindingOption: NSNegateBooleanTransformerName}];
					} else {
						[subView bind:NSValueBinding toObject:sampleController
						  withKeyPath:keyPath options:@{NSValidatesImmediatelyBindingOption: @YES}];
					}
				}
			} else if([subView isKindOfClass:NSPopUpButton.class]) {
				NSString *boundKeyPath = [@"selection." stringByAppendingString:subView.identifier];
				if([subView.identifier isEqualToString:@"boundSizeStandard"]) {
					/// a section has a popup button indicating the selected samples' size standard among the available size standards
					NSString *keyPath = @"tableContent.arrangedObjects";
					/// the content (menu) of the popup button represents the size standards
					[subView bind:NSContentBinding toObject:SizeStandardTableController.sharedController withKeyPath:keyPath options:nil];
					/// the values shown by menu items are the size standard names
					[subView bind:NSContentValuesBinding toObject:SizeStandardTableController.sharedController
					  withKeyPath:[keyPath stringByAppendingString:@".name"] options:nil];
					/// and the selected item is the size standard of the selected sample(s)
					[subView bind:NSSelectedObjectBinding toObject:sampleController withKeyPath: boundKeyPath options:nil];
					((NSPopUpButton *)subView).menu.delegate = self;

				} else if([subView.identifier isEqualToString:@"polynomialOrder"]) {
					/// the fitting method used by a size standard is the index of the selected menu item of a popup button showing the fitting method
					[subView bind:NSSelectedIndexBinding toObject:sampleController withKeyPath:boundKeyPath
						  options:@{NSMultipleValuesPlaceholderBindingOption : @(-1), NSNoSelectionPlaceholderBindingOption : @(-1)}];
				} else if([subView.identifier isEqualToString:@"peakThreshold"]) {
					[subView bind:NSContentBinding toObject:self withKeyPath:subView.identifier options:nil];
					[subView bind:NSSelectedObjectBinding toObject:sampleController
					  withKeyPath:[@"selection.ladderTrace." stringByAppendingString:subView.identifier]
						  options:@{NSMultipleValuesPlaceholderBindingOption : @(-1), NSNoSelectionPlaceholderBindingOption : @100}];
				}
			} else if([subView isKindOfClass:FittingView.class]) {
				/// we show the fit of the sizing with a special view (see FittingView class)
				[subView bind:@"samples" toObject:sampleController withKeyPath:@"content" options:nil];
			} else if([subView isKindOfClass:NSPathControl.class]) { /// the UI showing the path of the source file
				NSPathControl *control = (NSPathControl *)subView;
				control.action = @selector(pathControlIsClicked:);
				control.target = self;
				[subView bind:NSValueBinding toObject:sampleController withKeyPath:@"selection.fileURL" options:nil];
			}
		}
		return rowView;
	}
	/// for main section titles, we just use a standard row view. We could use any identifier.
	return [outlineView makeViewWithIdentifier:@"StandardRowView" owner:self];
}


- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
	if([item isKindOfClass:NSArray.class]) {
		/// the height of a row must be that of the row view as set in the xib.
		NSTableRowView *rowView = [outlineView makeViewWithIdentifier:[item firstObject] owner:nil];
		if(rowView) {
			return rowView.bounds.size.height;
		}
	}
	return 17.0;
}


- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item {
	/// each main section is a (floating) group item
	return [item isKindOfClass:NSString.class];
}


- (void)outlineView:(NSOutlineView *)outlineView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row {
	if(rowView.frame.size.height > 20.0) {
		/// We use a grey color for the rows within sections, to help differentiate section headers from their content.
		/// Setting the background color in rowViewForItem has no effect.
		rowView.backgroundColor = NSColor.windowBackgroundColor; // NSColor.alternatingContentBackgroundColors.lastObject;
	}
}

/// the expandable "items" are NSString instances (the group items). So they can be coded in a plist file as is.
- (id)outlineView:(NSOutlineView *)outlineView persistentObjectForItem:(id)item {
	return item;
}


- (id)outlineView:(NSOutlineView *)outlineView itemForPersistentObject:(id)object {
	return object;
}



#pragma mark - action sent by the path control



- (IBAction)pathControlIsClicked:(NSPathControl *)sender {		/// sent to the pathControl when it is clicked
	
	NSURL *clickedURL = sender.clickedPathItem.URL;
	if(!clickedURL) {
		return;
	}
	BOOL reachable = [NSWorkspace.sharedWorkspace selectFile:clickedURL.path inFileViewerRootedAtPath:@""];
	if(!reachable) {
		NSError *error = [NSError errorWithDescription:@"The destination could not be opened."
											suggestion: @"The file may have been moved or deleted since it was imported."];
		[NSApp presentError:error];
	}
}



@end


