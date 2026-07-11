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
#import "InfoTableRowView.h"
#import "SortCriteriaEditor.h"


@interface SampleInspectorController () {
	
	__weak IBOutlet InfoOutlineView *outlineView;  /// The outline view that constitute the sample inspector (designed in a nib).
												   /// The singleton object is the datasource and delegate of the outline view.
	
	CGFloat fittingViewHeight;					/// The height of the row showing the fitting view, which adapts to the table height.
	NSArray *sampleKeyPaths; 					/// The Chromatogram attribute names that we bind to value of NSTextfields that the inspector tab shows
}

/// The different peak thresholds the user can define for a ladder trace. We use this property to bind to the an NSPopupButton menu contents.
@property (nonatomic) NSArray<NSNumber *> *peakThreshold;

@property (nonatomic) NSDictionary<NSString *, NSString *> *actionForKeyPath;
@property (nonatomic) NSArray<NSString *>* outlineViewSections;
															
@end


@implementation SampleInspectorController

/// Implementation details:
/// The outline view (of which we are the delegate and datasource) has rows that are entirely designed in the nib file loaded in -init.
/// So to understand the implementation, one should inspect the nib file.



+ (instancetype)sharedController {
	static SampleInspectorController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = self.new;
	});
	return controller;
}


- (NSNibName)nibName {
	return @"SampleInspector";
}


- (instancetype)init {
	self = [super init];
	if(self) {
		sampleKeyPaths = [Chromatogram.entity.attributeKeys arrayByAddingObjectsFromArray:@[@"dye1", @"dye2",@"dye3", @"dye4", @"dye5"]];
		_peakThreshold = @[@10, @50, @100, @200, @500];
		fittingViewHeight = 500;
		/// the main section titles
		[self bind:@"outlineViewSections" toObject:NSUserDefaults.standardUserDefaults withKeyPath:SampleInspectorSections options:nil];
	}
	return self;
}


- (void)viewDidLoad {
	[super viewDidLoad];
	outlineView.backgroundColor = [NSColor colorNamed:ACColorNameViewBackgroundColor];
	outlineView.drawGridForMainSectionsOnly = YES;
	outlineView.autosaveExpandedItems = YES;
	outlineView.autosaveTableColumns = YES;
	outlineView.autosaveName = @"sampleInspector";
	[outlineView registerForDraggedTypes:@[StryperInspectorSectionDragType]];
}


- (void)viewDidAppear {
	[super viewDidAppear];
	[self updateFittingViewHeightAfterDelay];
}


- (void)viewDidLayout {
	[super viewDidLayout];
	if(self.view.inLiveResize) { /// This check is important, because when the outline view first appears, this method
								 /// if called successively, at times when updating the row height leaves the outline view
								 /// in an inconsistent state, which causes an exception when it is then resized horizontally.
		[self updateFittingViewHeight];
	}
}


#pragma mark - Delegate and datasource methods for the tableview

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
	NSInteger count = 0;
	if(item == nil) {
		/// the number of main (expandable) sections
		count = self.outlineViewSections.count;
	} else if([item isKindOfClass:NSString.class]) { /// each section is represented by a string. It has one child (the section's content)
		count = 1;
	}
	return count;
}



-(id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
	NSArray *outlineViewSections = self.outlineViewSections;
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
		
		NSArrayController *sampleController = SampleTableController.sharedController.samples;
		NSTableRowView *rowView = [outlineView makeViewWithIdentifier:[item firstObject] owner:self];
		for(NSView *subView in rowView.subviews) {
			if([subView isKindOfClass:NSTextField.class]) {
				NSTextField *textField = (NSTextField *)subView;
				if(textField.isEditable) {
					textField.delegate = self;
				}
				/// a row view contains text fields whose identifiers are attribute names of the Chromatogram entity, to simplify bindings
				if([sampleKeyPaths containsObject:textField.identifier]) {
					NSString *keyPath = [@"selection." stringByAppendingString:textField.identifier];
					if(textField.drawsBackground) {
						/// these textfields are those that show dye names.
						[textField bind:NSValueBinding toObject:sampleController
							withKeyPath:keyPath options:@{NSNoSelectionPlaceholderBindingOption: @"", NSMultipleValuesPlaceholderBindingOption: @"…"}];
						/// Since they draw their background, it is better to hide them when the selected samples don't have the corresponding dye
						[textField bind:NSHiddenBinding toObject:sampleController
							withKeyPath:keyPath options:@{NSValueTransformerNameBindingOption: NSIsNilTransformerName}];
						[textField bind:@"hidden2" toObject:sampleController		/// we also hide them when no sample is selected (the above binding is insufficient)
							withKeyPath:@"selectedObjects.@count" options:@{NSValueTransformerNameBindingOption: NSNegateBooleanTransformerName}];
					} else {
						[textField bind:NSValueBinding toObject:sampleController
							withKeyPath:keyPath options:@{NSValidatesImmediatelyBindingOption: @YES}];
					}
				}
			} else if([subView isKindOfClass:NSPopUpButton.class]) {
				NSButton *popup = (NSPopUpButton *)subView;
				popup.target = self;
				popup.action = @selector(popupClicked:);
				NSString *boundKeyPath = [@"selection." stringByAppendingString:subView.identifier];
				if([popup.identifier isEqualToString:ChromatogramAppliedSizeStandardKey]) {
					/// a section has a popup button indicating the selected samples' size standard among the available size standards
					NSString *keyPath = @"arrangedObjects";
					/// the content (menu) of the popup button represents the size standards
					[popup bind:NSContentBinding toObject:SizeStandardTableController.sharedController withKeyPath:keyPath options:nil];
					/// the values shown by menu items are the size standard names
					[popup bind:NSContentValuesBinding toObject:SizeStandardTableController.sharedController
					withKeyPath:[keyPath stringByAppendingString:@".name"] options:@{NSNullPlaceholderBindingOption:@"(None)"}];
					/// and the selected item is the size standard of the selected sample(s)
					[popup bind:NSSelectedObjectBinding toObject:sampleController withKeyPath: boundKeyPath options:nil];
					popup.menu.delegate = self;
					
				} else if([popup.identifier isEqualToString:@"polynomialOrder"]) {
					/// the fitting method used by a size standard is the index of the selected menu item of a popup button showing the fitting method
					[popup bind:NSSelectedIndexBinding toObject:sampleController withKeyPath:boundKeyPath
						options:@{NSMultipleValuesPlaceholderBindingOption : @(-1), NSNoSelectionPlaceholderBindingOption : @(-1)}];
				} else if([popup.identifier isEqualToString:@"peakThreshold"]) {
					[popup bind:NSContentBinding toObject:self withKeyPath:subView.identifier options:nil];
					[popup bind:NSSelectedObjectBinding toObject:sampleController
					withKeyPath:[@"selection.ladderTrace." stringByAppendingString:subView.identifier]
						options:@{NSMultipleValuesPlaceholderBindingOption : @(-1), NSNoSelectionPlaceholderBindingOption : @100}];
				}
			} else if([subView isKindOfClass:FittingView.class]) {
				/// we show the fit of the sizing with a special view (see FittingView class)
				[subView bind:@"samples" toObject:sampleController withKeyPath:@"selectedObjects" options:nil];
			} else if([subView isKindOfClass:NSPathControl.class]) { /// the UI showing the path of the source file
				NSPathControl *control = (NSPathControl *)subView;
				control.action = @selector(pathControlIsClicked:);
				control.target = self;
				[control bind:NSValueBinding toObject:sampleController withKeyPath:@"selection.fileURL" options:nil];
			}
		}
		return rowView;
	}
	/// for main section titles:
	return InfoTableRowView.new;
}



- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
	if([item isKindOfClass:NSArray.class]) {
		if([item containsObject:@"Sizing"]) {
			return fittingViewHeight;
		}
		/// the height of a row must be that of the row view as set in the xib.
		NSTableRowView *rowView = [outlineView makeViewWithIdentifier:[item firstObject] owner:nil];
		if(rowView) {
			return rowView.bounds.size.height;
		}
	}
	return 17.0;
}


static NSPasteboardType StryperInspectorSectionDragType = @"org.jpeccoud.stryper.inspectorSectionDragType";

- (id<NSPasteboardWriting>)outlineView:(NSOutlineView *)outlineView pasteboardWriterForItem:(id)item {
	/// The mains sections (parent rows) of the outline view can be rearranged by dragging.
	NSString *sectionTitle = item; ///
	if([item isKindOfClass:NSArray.class]) {
		/// This correspond to a child row being dragged. The item is an array containing the section title
		/// We currently don't allow dragging child row (drag methods are however ready for that, if needed)
		//		sectionTitle = [item firstObject];
	}
	if([sectionTitle isKindOfClass:NSString.class]) {
		NSPasteboardItem *pasteBoardItem = NSPasteboardItem.new;
		[pasteBoardItem setString:sectionTitle.copy forType:StryperInspectorSectionDragType];
		return pasteBoardItem;
	}
	return nil;
}


- (void)outlineView:(NSOutlineView *)outlineView draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint forItems:(NSArray *)draggedItems {
	
	if(NSCursor.currentCursor != NSCursor.closedHandCursor) {
		[NSCursor.closedHandCursor push];
	}
	
	NSMutableIndexSet *rowIndexes = NSMutableIndexSet.new;
	/// If a main section is dragged, we also dragged its child row, hence the image is taller than the row.
	BOOL topAligned = NO; /// This will ensure correct position of the dragging image
	for (id item in draggedItems) {
		if(![outlineView parentForItem:item]) {
			/// Which means a main section is dragged
			/// This check does not work if some parents + children are dragged at the same time, but this is not allowed
			/// since we don't allow selecting rows in this outline view.
			topAligned = YES;
		}
		NSInteger row = [outlineView rowForItem:item];
		if (row >= 0) {
			[rowIndexes addIndex:row];
		}
	}
	
	[SortCriteriaEditor setRowImagesForDraggingSession:session fromTableView:outlineView atRowIndexes:rowIndexes forPoint:screenPoint alignWithTop:topAligned];
	
}



- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index {
	NSString *draggedRowId = [info.draggingPasteboard.pasteboardItems.firstObject stringForType:StryperInspectorSectionDragType];
	NSArray *outlineViewSections = self.outlineViewSections;
	NSInteger sourceIndex = [outlineViewSections indexOfObject:draggedRowId];
	
	if(sourceIndex != NSNotFound) {
		if(item == nil) { /// The destination is the root
			if(index >= sourceIndex +2 || index < sourceIndex || index < 0) {
				/// Dragging only makes sens if the destination index is not at least 2+ the source (dropping an item just below itself would not rearrange anything)
				/// Neither would dropping an item just above itself.
				if(!(sourceIndex >= outlineViewSections.count && index < 0)) {
					/// index of –1 means after the last row, which would not rearrange anything if it is the last row that is dragged
					return NSDragOperationMove;
				}
			}
		} else {
			/// We allow dropping a main section after the child of another section, which will actually drop it after this other section
			/// This permit wider drop targets.
			NSInteger destinationIndex = [outlineViewSections indexOfObject:item];
			if(destinationIndex != sourceIndex && destinationIndex != sourceIndex-1 && index == 1) {
				return NSDragOperationMove;
			}
		}
	}
	return NSDragOperationNone;
}


- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id<NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index {
	NSString *draggedRowId = [info.draggingPasteboard.pasteboardItems.firstObject stringForType:StryperInspectorSectionDragType];
	NSArray *outlineViewSections = self.outlineViewSections;
	NSInteger sourceIndex = [outlineViewSections indexOfObject:draggedRowId];
	
	if(sourceIndex != NSNotFound) {
		NSInteger nSections = outlineViewSections.count;
		if(item == nil) { /// The destination is the root
			if(index > sourceIndex) {
				/// When a section is moved down, we need to deduce 1 from the destination index (which represents the section that will be moved)
				index--;
			}
			if(index == -1 || index >= nSections) {
				/// Here, the dropped section will be the last.
				index = nSections-1;
			}
		}
		
		if(item != nil) {
			/// The destination is not the root, but another section.
			/// In this case, we still drop at the root (we have to) below this other section.
			index = [outlineViewSections indexOfObject:item];
			if(index < sourceIndex) {
				index++;
			}
		}
		
		if(index >= 0 & index < nSections) {
			/// We update the outline view and the model.
			[self moveSectionFromRow:sourceIndex toRow:index];
			[self updateFittingViewHeight];
			return YES;
		}
	}
	return NO;
}


-(void)moveSectionFromRow:(NSInteger)sourceRow toRow:(NSInteger)destinationRow {
	NSInteger nRow = outlineView.numberOfRows;
	NSInteger nSections = self.outlineViewSections.count;
	if(sourceRow >= 0 & sourceRow < nRow & sourceRow < nSections & destinationRow >= 0 & destinationRow < nRow & destinationRow < nSections) {
		[outlineView moveItemAtIndex:sourceRow inParent:nil toIndex:destinationRow inParent:nil];
		NSMutableArray *rearrangedOutlineViewSections = self.outlineViewSections.mutableCopy;
		id draggedRowID = [rearrangedOutlineViewSections objectAtIndex:sourceRow];
		[rearrangedOutlineViewSections removeObjectAtIndex:sourceRow];
		[rearrangedOutlineViewSections insertObject:draggedRowID atIndex:destinationRow];
		[NSUserDefaults.standardUserDefaults setObject:rearrangedOutlineViewSections.copy forKey:SampleInspectorSections];
		CDUndoManager *undoManager = (CDUndoManager *)self.undoManager;
		[undoManager forceActionName:@"Move Inspector Section"];
		[undoManager registerUndoWithTarget:self handler:^(id  _Nonnull target) {
			[self moveSectionFromRow:destinationRow toRow:sourceRow];
		}];
	}
}


-(void)updateFittingViewHeightAfterDelay {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self updateFittingViewHeight];
	});
}


-(void) updateFittingViewHeight {
	CGFloat newHeight = outlineView.bounds.size.width;
	NSInteger row = [outlineView rowForItem:@[@"Sizing"]];
	if(row >= 0) {
		NSRect rect = [outlineView rectOfRow:row];
		NSView *clipView = outlineView.superview;
		rect = [clipView convertRect:rect fromView:outlineView];
		CGFloat margin = clipView.bounds.size.height - NSMinY(rect) - 3.0;
		if(margin < newHeight) {
			newHeight = MAX(150.0, margin);
		}
		
		if(fabs(newHeight - fittingViewHeight) >= 1) {
			fittingViewHeight = newHeight;
			NSAnimationContext.currentContext.duration = 0;
			[NSAnimationContext beginGrouping];
			[outlineView beginUpdates];
			[outlineView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndex:row]];
			[NSAnimationContext endGrouping];
			[outlineView endUpdates];
		}
	}
}


- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item {
	/// each main section is a (floating) group item // Disabled, as the outline view is not configured to show group rows
	return NO;// [item isKindOfClass:NSString.class];
}




- (void)outlineViewItemDidExpand:(NSNotification *)notification {
	[self updateFittingViewHeightAfterDelay];
}


- (void)outlineViewItemDidCollapse:(NSNotification *)notification {
	[self updateFittingViewHeightAfterDelay];
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
	if(clickedURL) {
		BOOL reachable = [NSWorkspace.sharedWorkspace selectFile:clickedURL.path inFileViewerRootedAtPath:@""];
		if(!reachable) {
			NSError *error = [NSError errorWithDescription:@"The destination could not be opened."
												suggestion: @"The file may have been moved or deleted since it was imported."];
			[NSApp presentError:error];
		}
	}
}


- (NSDictionary<NSString *,NSString *> *)actionForKeyPath {
	if(!_actionForKeyPath) {
		_actionForKeyPath = @{ChromatogramSampleNameKey: @"Rename Sample",
							  ChromatogramCommentKey: @"Edit Sample Comment",
							  ChromatogramAppliedSizeStandardKey: @"Change Size Standard",
							  @"polynomialOrder": @"Change Fitting Method",
							  @"peakThreshold": @"Change Peak Detection Threshold",
		};
	}
	return _actionForKeyPath;
}


- (void)controlTextDidEndEditing:(NSNotification *)notification {
	NSControl *control = notification.object;
	[self setActionNameForControl:control];
}


- (void)popupClicked:(NSPopUpButton *)sender {
	[self setActionNameForControl:sender];
}


- (void)setActionNameForControl:(NSControl *)sender {
	NSString *actionName = self.actionForKeyPath[sender.identifier];
	if(actionName) {
		[self.undoManager setActionName:actionName];
	}
}


@end


