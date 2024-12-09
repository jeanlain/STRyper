//
//  DetailedViewController.m
//  STRyper
//
//  Created by Jean Peccoud on 26/08/12.
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



#import "DetailedViewController.h"
#import "Mmarker.h"
#import "MainWindowController.h"
#import "SampleTableController.h"
#import "MarkerView.h"
#import "TraceScrollView.h"
#import "STableRowView.h"
#import "RulerView.h"
#import "SizeStandardTableController.h"
#import "SizeStandard.h"

@interface DetailedViewController ()

/************ properties that we bind to the user defaults equivalent ******/


/// Whether the `topFluoMode` property  returns `topFluoModeHighestPeak`. We use it to bind to the equivalent property in traceViews, as traceViews themselves auto scale
@property (nonatomic) BOOL autoScaleToHighestPeak;

/// The default start size for the visibleRange of traceViews
@property (nonatomic) float defaultStartSize;

/// The default end size for the visibleRange of traceViews
@property (nonatomic) float defaultEndSize;

/// The default visibleRange of traceViews, derived from the defaultStartSize and defaultEnSize
@property (nonatomic) BaseRange defaultRange;


/// Whether the content the outline views shows corresponds to genotypes.
@property (nonatomic) BOOL showGenotypes;

/// Whether the outline views shows marker. We bind this property to the visibility of certain buttons.
@property (nonatomic) BOOL showMarkers;

/// A button that we may show to ask the user for confirmation to load a large number or samples or genotypes in the outline view
@property (nonatomic) NSButton *loadContentButton;

/// A textfield indicating the number of stacked samples that are shown, in place of the table header view
@property (nonatomic) NSTextField *stackedSampleTextfield;

/// The channels (as integers) that are currently displayed
@property (nonatomic) NSArray<NSNumber *> *displayedChannels;

/// the height of rows showing traces or markers, given the window size and the number of traces per window that the user wishes to see.
/// Its setter makes changes on the outline view
@property (nonatomic) float traceRowHeight;

@end



@implementation DetailedViewController

/// Notes on the implementation:
/// We use an outline view to show content, as it can convey the hierarchy between two entities:
/// ``Chromatogram``/``Genotype`` objects , which are represented as regular rows, as in the sample table. They are the "parents".
///
/// The children are the chromatograms' traces (``Trace`` class), which show in custom row views.
/// These row views don't have any table cell views.
///
/// This hierarchy facilitates the managing of the data source and showing/hiding channels.
/// For each genotypes, there is only one channel per view at the range corresponding to the marker. Some setting buttons become hidden (stack channels and traces, and sync view), as they aren't relevant
///
/// When samples are selected, there are several display modes (see StackMode typdef)
/// When genotypes are selected, a regular row showing samples information in several column is followed by a tall row showing the trace of the sample at the corresponding marker
/// When markers are selected, one tall row per marker shows bins and the marker range (like in genotype mode when bin editing is enabled, but without the trace behind).
///
/// We don't use many of the TableViewController methods as the user cannot select nor remove items from the outline view, but we use those creating columns, the table header menu and some table cell views, mainly

{
	NSArray<NSButton *> *channelButtons;	/// array containing references to the round buttons allowing to show/hide channels.
											/// We use this array for quicker access as there are other buttons
	
	__weak NSOutlineView *traceOutlineView;  /// the outline view showing traces and/or markers, of which this object is the delegate and which is also the view we control
	
	BaseRange referenceRange;				/// the synchronized visible range of traceViews
	float referenceTopFluoLevel;			/// the synchronize top fluo level of traceViews
	
	NSMutableSet<TraceView *> *traceViews;	/// the set of visible trace views that we use to synchronize them
											/// I believe it is faster than enumerating all rows of the outline view at each scroll step
	
}

@synthesize traceRowHeight = _traceRowHeight;

static NSArray<NSString *> *channelPreferenceKeys;				/// a convenience array we use to bind values of channel buttons to the corresponding user default key and to determine which button to disable
																
static NSString* const applySizeStandardMenuIdentifier = @"applySizeStandardMenuIdentifier";


static const float defaultRowHeight = 20.0;
static const float minTraceRowHeight = 40.0;
static const float maxTraceRowHeight = 1000.0;


+ (instancetype)sharedController {
	static DetailedViewController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = self.new;
	});
	return controller;
}

- (NSNibName)nibName {
	return @"RightPane";
}


-(NSDictionary *)columnDescription {
	return SampleTableController.sharedController.columnDescription;
}


- (NSTableView *)viewForCellPrototypes {
	return SampleTableController.sharedController.tableView;
}


- (NSArray<NSString *> *)orderedColumnIDs {
	return [SampleTableController.sharedController orderedColumnIDs];
}


- (nullable NSArrayController *)tableContent {
	return nil;
}


- (void)viewDidLoad {
	channelPreferenceKeys = @[ShowChannel0, ShowChannel1, ShowChannel2, ShowChannel3, ShowChannel4];
	NSMutableArray *channelButtonArray = NSMutableArray.new;
	
	[self.tableView bind:NSSortDescriptorsBinding toObject:SampleTableController.sharedController.samples withKeyPath:NSStringFromSelector(@selector(sortDescriptors)) options:nil];
	
	NSUserDefaults *standardUserDefaults = NSUserDefaults.standardUserDefaults;
	
	/// we bind the contents to show in the detailed view to the selected objects of the source controller.
	/// The detailed view will then show the selected objects from the various sources
	[self bind:NSStringFromSelector(@selector(contentArray)) toObject:MainWindowController.sharedController withKeyPath:@"sourceController.tableContent.selectedObjects" options:nil];
	[self bind:NSStringFromSelector(@selector(stackMode))
	  toObject:standardUserDefaults withKeyPath:TraceStackMode options:nil];
	[self bind:NSStringFromSelector(@selector(numberOfRowsPerWindow)) 
	  toObject:standardUserDefaults withKeyPath:TraceRowsPerWindow options:nil];
	[self bind:NSStringFromSelector(@selector(synchronizeViews)) 
	  toObject:standardUserDefaults withKeyPath:SynchronizeViews options:nil];
	[self bind:NSStringFromSelector(@selector(topFluoMode)) 
	  toObject:standardUserDefaults withKeyPath:TraceTopFluoMode options:nil];

	/// we apply bindings to the display buttons
	/// we make an array of some preferences keys to bind to some buttons, based on the button tags (used to fetch the corresponding key in the array):
	NSArray *prefKeys = @[TraceTopFluoMode, SynchronizeViews, ShowOffScale, ShowBins, TraceStackMode];
	for (NSControl *control in self.view.subviews) {
		if([control isKindOfClass: NSButton.class] || [control isKindOfClass: NSSegmentedControl.class]) {
			/// all buttons must be hidden when the outline view shows markers, except the slider that controls row height
			[control bind:NSHiddenBinding toObject:self withKeyPath:NSStringFromSelector(@selector(showMarkers)) options:nil];
			if(control.tag >= 0 || control.tag == -5) {
				/// some buttons must be also hidden when it shows genotypes. We use their tag to determine which.
				[control bind:@"hidden2" toObject:self withKeyPath:NSStringFromSelector(@selector(showGenotypes)) options:nil];
				if(control.tag < 5 && control.tag >=0) {
					/// these are buttons controlling the channel to show. Their tags represent the channels from 0 to 4.
					[channelButtonArray addObject:control];
					[control bind:NSValueBinding toObject:standardUserDefaults withKeyPath:channelPreferenceKeys[control.tag] options:nil];
				}
			}
			if(control.tag < 0) {
				if([control isKindOfClass: NSButton.class]) {
					NSString *keyPath = prefKeys[-control.tag -1];
					[control bind:NSValueBinding toObject:standardUserDefaults withKeyPath:keyPath options:nil];
					if([keyPath isEqualToString:SynchronizeViews]) {
						/// The button that controls the horizontal synchronization is disabled when genotypes are shown.
						[control bind:NSEnabledBinding toObject:self
						  withKeyPath:NSStringFromSelector(@selector(showGenotypes))
							  options:@{NSValueTransformerNameBindingOption:NSNegateBooleanTransformerName}];
					}
				} else if([control isKindOfClass: NSSegmentedControl.class]) {
					[control bind:NSSelectedIndexBinding toObject:standardUserDefaults withKeyPath:prefKeys[-control.tag -1] options:nil];
				}
			}
		} else if([control isKindOfClass:NSSlider.class]) {
			[control bind:NSValueBinding toObject:standardUserDefaults withKeyPath:TraceRowsPerWindow options:nil];
		}
	}
	
	channelButtons = [NSArray arrayWithArray:channelButtonArray];
	
	traceOutlineView = (NSOutlineView *)self.tableView;
	
	[super viewDidLoad];
	
	/// We make sure the sample name column is column 0
	int i = 0;
	for(NSTableColumn *column in traceOutlineView.tableColumns) {
		if([column.identifier isEqualToString:@"sampleNameColumn"]) {
			if(i != 0) {
				[traceOutlineView moveColumn:i toColumn:0];
			}
			break;
		}
		i++;
	}
	
	[[NSNotificationCenter defaultCenter]addObserver:self 
											selector:@selector(windowDidResize:)
												name:NSWindowDidResizeNotification
											  object:traceOutlineView.window];  /// to react to the window changing size and set the height of rows accordingly
	
	[self bind:NSStringFromSelector(@selector(defaultStartSize)) toObject:standardUserDefaults withKeyPath:DefaultStartSize options:nil];
	[self bind:NSStringFromSelector(@selector(defaultEndSize)) toObject:standardUserDefaults withKeyPath:DefaultEndSize options:nil];
	
	/// we set the default visible range of trace views
	referenceRange = MakeBaseRange(-1, -1);
	float start = [standardUserDefaults floatForKey:ReferenceStartSize];
	float end = [standardUserDefaults floatForKey:ReferenceEndSize];
	if(end > 0) {
		referenceRange = MakeBaseRange(start, end - start);
	}
	
	if(!self.displayedChannels) {
		[self updateDisplayedChannels];
	}
	
	referenceTopFluoLevel = -1.0;
	
	traceViews = NSMutableSet.new;
}



- (void)viewDidAppear {
	[super viewDidAppear];
	/// We restore the selection now. If we did it earlier, the outline view would not show at its final size,
	/// which may cause issue with trace rows.
	if(!self.contentArray) {
		/// The view may also appear when it is unhidden, this check should avoid restoring the selection
		/// more than once. TO IMPROVE.
		[MainWindowController.sharedController restoreSelection];
	}
}


- (NSButton *)loadContentButton {
	if(!_loadContentButton && traceOutlineView.superview) {
		/// we place the button asking for confirmation to load the content at the center of the visible rectangle of the outline view, i.e. in its clipview
		/// placing it in the enclosing scrollview works, but the centering of the button (below) has no effect
		NSView *view = traceOutlineView.superview;
		_loadContentButton = [traceOutlineView makeViewWithIdentifier:@"loadContentButton" owner:self];
		_loadContentButton.translatesAutoresizingMaskIntoConstraints = NO;
		[view addSubview:_loadContentButton];
		/// we center the button horizontally and vertically in its view
		[[_loadContentButton.centerXAnchor constraintEqualToAnchor:view.centerXAnchor] setActive:YES];
		[[_loadContentButton.bottomAnchor constraintEqualToAnchor:view.centerYAnchor] setActive:YES];
		_loadContentButton.target = self;
		_loadContentButton.action = @selector(loadContent:);
		
	}
	return _loadContentButton;
}


- (NSTextField *)stackedSampleTextfield {
	if(!_stackedSampleTextfield && traceOutlineView.headerView) {
		_stackedSampleTextfield = [NSTextField labelWithString:@"Several samples stacked"];
		NSTableHeaderView *headerView = traceOutlineView.headerView;
		_stackedSampleTextfield.translatesAutoresizingMaskIntoConstraints = NO;
		[headerView.superview addSubview:_stackedSampleTextfield];
		[[_stackedSampleTextfield.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor] setActive:YES];
		[[_stackedSampleTextfield.centerXAnchor constraintEqualToAnchor:headerView.centerXAnchor] setActive:YES];
	}
	return _stackedSampleTextfield;
}


- (BOOL)shouldMakeTableHeaderMenu {
	return YES;
}


- (BOOL)canSortByMultipleColumns {
	return NO;
}



#pragma mark - methods to populate the outline view showing traces (or markers)


- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
	if (item == nil) {
		NSInteger count = self.contentArray.count;		/// the number of parent rows is by default the number of items in the content array
		if(count == 0 || self.contentArray.firstObject == NSNull.null) {
			return 0;
		}
		return (self.stackMode == stackModeSamples && count > 1 && !self.showGenotypes && !self.showMarkers)? self.displayedChannels.count : count;  /// if we stack sample curves, the number of rows is the number of channels to show
	}
	if([item isKindOfClass: Genotype.class]) {
		return 1;	/// a genotype has one child, which is the trace corresponding to the marker's channel for the chromatogram
	}
	
	if([item isKindOfClass: Chromatogram.class]) {
		/// the number of children of a chromatogram depends on whether the channels are stacked or not
		return (self.stackMode == stackModeChannels && !self.showGenotypes)? 1 : self.displayedChannels.count;  /// which is the number of rows in each sample (1 if channels overlap, or the number of channels to show separately, depending on the view setting)
	}
	return 0;	/// other types of items have no children as they are represented by trace rows. They are not expandable.
}


- (id) outlineView:(id)outlineView child:(NSInteger)index ofItem:(id)item {
	NSInteger count = self.contentArray.count;
	if (item == nil) {  /// the top-level rows
		if (self.stackMode == stackModeSamples && count > 1 && !self.showGenotypes && !self.showMarkers) {
			/// here, samples are stacked
			/// if the child index, which should correspond to the channel to show, exceeds the displayedChannels array, we return a null object
			/// (but this would mean there is a bug somewhere)
			if(self.displayedChannels.count <= index) {
				return NSNull.null;
			}
			return [self tracesForChannel:self.displayedChannels[index].intValue]; 	/// if a row should show all traces of a given channel in an array, we return these traces
		}
		/// here, we don't stack samples, so we simply return the item at the corresponding index from the content array
		/// This could be a chromatogram, a marker, or a genotype
		if(count < index+1) {
			return NSNull.null;
			/// this also prevents a crash. But if it we return a null object, it means there's a bug somewhere
		}
		/// else we return the sample/genotype at the given index (row number), whose metadata will populate standard rows with text fields
		return self.contentArray[index] ;
	}
	if([item isKindOfClass:Genotype.class]) {
		/// When the parent is a genotype, there is just one trace row below the parent row. The trace row will load the genotype, hence we need to return it
		/// but we must differentiate the child from the parent (to avoid an infinite loop).
		/// So we enclose the genotype in an NSSet (there may be be a more elegant solution for that). NSArray is already used for traces.
		return [NSSet setWithObject:item];
	}
	
	/// If we're here, it means that the parent is a sample.
	if(self.stackMode == stackModeChannels && !self.showGenotypes) {
		/// if we stack channels in the same view (the second condition is probably redundant),
		/// we return the sample, but enclosed in an NSSet to differentiate the child from the parent
		return [NSSet setWithObject:item];
	}
	/// if we're here, it means that we don't stack channels in the same view
	if(self.displayedChannels.count <= index) {
		return NSNull.null;
	}
	Trace *trace =[item traceForChannel: self.displayedChannels[index].intValue];	/// the child row will show the sample's trace for the correct channel
	if(!trace) {
		return NSNull.null;		/// if there is no trace for that channel, we return a null object.
	}
	return @[trace];  			/// else we return the trace in an array (a trace view is designed to show multiple traces, which we always return in an array)
}


- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
	return YES;		/// all items that have children are expanded (and can't be collapsed)
}


- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
	
	if([item isKindOfClass: Genotype.class]) {
		return [item sample];
		/// for a regular row representing a genotype, we actually show the information from the sample.
		/// We don't show genotype information in the cells (status, marker, allele size, etc.). We could do that, but this would require replacing the columns
		/// Plus, all genotype information is visible in the trace view themselves (marker name, color, alleles...)
	}
	return item;  /// else, we return nil because the row corresponding to the item has no cell view (see viewForTableColumn:)
}


- (NSTableRowView *)outlineView:(NSOutlineView *)outlineView rowViewForItem:(id)item {
	if(item == NSNull.null || ([item isKindOfClass:NSArray.class] && [item count] == 0)) {
		/// case where there is no trace for the required channel. We have a special row view in the nib,
		/// which has a textfield showing that there is no data for the channel
		return [outlineView makeViewWithIdentifier:@"noTraceRowViewKey" owner:self];
	}
	
	if([item isKindOfClass: Chromatogram.class] || [item isKindOfClass:Genotype.class]) {
		/// if the item is a chromatogram or a genotype, we return a standard row view that will include cells showing sample information
		/// (the identifier could be any identifier not corresponding to a view present in the xib)
		return [outlineView makeViewWithIdentifier:@"StandardRowView" owner:self];
	}
	
	///otherwise, the row should show a trace-view that will load traces, a genotype, or a marker
	STableRowView *rowView;
	TraceView *traceView;
	
	if([item isKindOfClass:NSSet.class]) {
		/// Genotype and Chromatogram objects are encapsulated as sole objects in an NSSet.
		item = [item anyObject];
	}
	
	rowView = [self rowViewForItem:item];
	
	if(rowView) {
		traceView = [rowView viewWithTag:1];
	} else {
		NSRect frame = NSMakeRect(0, 0, outlineView.bounds.size.width, self.traceRowHeight + outlineView.intercellSpacing.height);
		rowView = [STableRowView.alloc initWithFrame:frame];
		TraceScrollView *scrollView = [[TraceScrollView alloc] initWithFrame:frame];
		scrollView.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;
		[rowView addSubview:scrollView];
		
		traceView = [[TraceView alloc] initWithFrame:frame];
		traceView.delegate = self;
		scrollView.documentView = traceView;
		
		NSUserDefaults *standardUserDefaults = NSUserDefaults.standardUserDefaults;
		[traceView bind:ShowBinsBinding toObject:standardUserDefaults withKeyPath:ShowBins options:nil];
		[traceView bind:ShowPeakTooltipsBinding toObject:standardUserDefaults withKeyPath:ShowPeakTooltips options:nil];
		[traceView bind:ShowOffScaleRegionsBinding toObject:standardUserDefaults withKeyPath:ShowOffScale options:nil];
		[traceView bind:ShowRawDataBinding toObject:standardUserDefaults withKeyPath:ShowRawData options:nil];
		[traceView bind:PaintCrosstalkPeakBinding toObject:standardUserDefaults withKeyPath:PaintCrosstalkPeaks options:nil];
		[traceView bind:MaintainPeakHeightsBinding toObject:standardUserDefaults withKeyPath:MaintainPeakHeights options:nil];
		[traceView bind:AutoScaleToHighestPeakBinding toObject:self withKeyPath:@"autoScaleToHighestPeak" options:nil];
		[traceView bind:IgnoreCrossTalkPeaksBinding toObject:standardUserDefaults withKeyPath:IgnoreCrosstalkPeaks options:nil];
		[traceView bind:DisplayedChannelsBinding toObject:self withKeyPath:@"displayedChannels" options:nil];
		[traceView bind:DefaultRangeBinding toObject:self withKeyPath:@"defaultRange" options:nil];
		[scrollView bind:AllowSwipeBetweenMarkersBinding toObject:standardUserDefaults withKeyPath:SwipeBetweenMarkers options:nil];
		
		NSPopUpButton *popup = traceView.rulerView.applySizeStandardButton;
		if(popup) {
			NSMenu *menu = NSMenu.new;
			menu.identifier = applySizeStandardMenuIdentifier;
			NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Apply Size Standard" action:nil keyEquivalent:@""];
			item.representedObject = traceView; /// We will need to identify the view to determine the sample(s) it shows.
												/// In principle, this should not create a retain cycle (the traceView does not have strong ownership of the ruler view)
												/// The `target` property of item cannot be used instead, as it apparently doesn't work here (possibly because the item
												/// has no action, and I don't want to set a dummy action for this).
			[menu addItem:item];
			menu.delegate = self;
			popup.menu = menu;
		}
	}
	
	[traceView loadContent:item];
	[traceViews addObject:traceView];

	return  rowView;
}


/// Returns an appropriate rowView for an item shown in a ``TraceView``.
///
/// The returned row view has a trace view which as loaded the same panel as the item to show in the trace,
/// if such row view is available.
/// - Parameter item: The item to show in the row view.
- (__kindof NSTableRowView *)rowViewForItem:(id)item {
	STableRowView *rowView;
	Panel *panelToShow;
	ChannelNumber channelToShow = blueChannelNumber;
	if([item isKindOfClass:NSArray.class]) {
		Trace *trace = [item firstObject];
		if(!trace.isLadder) {
			panelToShow = trace.chromatogram.panel;
			channelToShow = trace.channel;
		}
	} else if([item isKindOfClass:Genotype.class]) {
		Mmarker *marker = ((Genotype *)item).marker;
		panelToShow = marker.panel;
		channelToShow = marker.channel;
	} else if([item isKindOfClass:Chromatogram.class] && self.displayedChannels.count == 1) {
		channelToShow = self.displayedChannels.firstObject.shortValue;
		if(channelToShow < orangeChannelNumber) {
			Chromatogram *sample = (Chromatogram *)item;
			panelToShow = sample.panel;
		}
	}
	if(panelToShow) {
		NSString *ID = [NSString stringWithFormat:@"%@ %@ %d", panelToShow.name, panelToShow.parent.name, channelToShow];
		rowView = [traceOutlineView makeViewWithIdentifier:ID owner:self];
	}
	if(!rowView) {
		rowView = [traceOutlineView makeViewWithIdentifier:@"traceRowView" owner:self];
	}
	return rowView;
}



- (void)outlineView:(NSOutlineView *)outlineView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row {
	if ([rowView.identifier isEqualToString:@"noTraceRowViewKey"])  {
		rowView.backgroundColor = NSColor.orangeColor;		/// setting this in rowViewForItem: has no effect, for some reason
	}
}


- (void)outlineView:(NSOutlineView *)outlineView didRemoveRowView:(NSTableRowView *)rowView forRow:(NSInteger)row {
	if ([rowView isKindOfClass:STableRowView.class]) {
		TraceView* traceView = [rowView viewWithTag:1];
		if(traceView) {
			Panel *panel = traceView.panel;
			NSString *ID = @"traceRowView";
			if(panel && traceView.trace) {
				/// We give the row view an identifier that represents the panel and the channel of the trace view.
				/// If needed we can retrieve a view that has loaded a particular panel for a channel (see ``rowViewForItem:``).
				/// This allows the trace view (and marker view) to reuse labels for bins and markers, improving load time.
				ID = [NSString stringWithFormat:@"%@ %@ %d", panel.name, panel.parent.name, traceView.channel];
			}
			rowView.identifier = ID;
			[traceView prepareForReuse];
			[traceViews removeObject:traceView];
		}
	}
}


- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
	if (![item isKindOfClass: Chromatogram.class] && ![item isKindOfClass: Genotype.class]) {
		return nil;  					/// if the item isn't a Chromatogram, the row has no cell (traces and markers are shown in the row view)
	}
	/// We generate a future identifier for the view to avoid configuring it several times
	NSString *ID = [tableColumn.identifier stringByAppendingString:@"_configured"];
	
	NSTableCellView *cellView = [outlineView makeViewWithIdentifier:ID owner:self];
	if(cellView) {
		return cellView;
	}
		
	if([tableColumn.identifier isEqualToString:@"sampleNameColumn"]) {
		/// For this column, the cell view prototype is different from that of the sample table.
		/// It has a button to allow revealing the represented item in the source list (sample table or genotype table)
		cellView = [outlineView makeViewWithIdentifier:@"sampleNameCellView" owner:self];
		NSTextField *textField = cellView.textField;
		if(textField) {
			[textField bind:NSValueBinding toObject:cellView withKeyPath:@"objectValue.sampleName" options:@{NSValidatesImmediatelyBindingOption:@YES}];
		}
		NSButton *button = [cellView viewWithTag:1];
		if(button) {
			button.action = @selector(revealInList:);
			button.target = self;
			button.showsBorderOnlyWhileMouseInside = YES; /// This is the only reason why we configure this view in code,
														  /// The rest could have been configured in IB.
		}
		cellView.identifier = ID;
		return cellView;
	}
	
	/// otherwise, we return table cells views whose prototype are in the sampleTable
	cellView = (NSTableCellView *)[super tableView:outlineView viewForTableColumn:tableColumn row:0];
	NSTextField *textField = cellView.textField;
	if(textField) {
		textField.controlSize = NSControlSizeRegular;
		textField.font = [NSFont systemFontOfSize:13.0];	/// the font is a little bigger than in the sample table
	}
	cellView.identifier = ID;
	return cellView;
}



- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
	return NO;  /// the outline view is not meant to select any row:
	
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldShowOutlineCellForItem:(id)item {
	return NO;   /// we don't allow collapsing anything.
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldCollapseItem:(id)item {
	return NO;
}


- (NSArray<Trace *> *)tracesForChannel:(NSInteger) channel {
	/// we return all traces of a give channel. Called when samples are stacked
	NSMutableArray *traces = [NSMutableArray arrayWithCapacity:self.contentArray.count];
	for(Chromatogram *sample in self.contentArray) {
		if([sample respondsToSelector:@selector(traceForChannel:)]) {
			Trace *trace = [sample traceForChannel:channel];
			if(trace) {
				[traces addObject:trace];
			}
		}
	}
	return traces;
}

#pragma mark - setting contents

- (void)setContentArray:(NSArray *)content {
	if(content.count > 0) {
		BOOL showMarkers = [content.firstObject isKindOfClass: Mmarker.class];
		BOOL showGenotypes = [content.firstObject isKindOfClass: Genotype.class];
		BOOL changedMode = NO;
		if(showMarkers != self.showMarkers) {
			changedMode = YES;
			self.showMarkers = showMarkers;
		}
		
		if(showGenotypes != self.showGenotypes) {
			changedMode = YES;
			self.showGenotypes = showGenotypes;
		}
		
		if(changedMode && !showMarkers && !showGenotypes) {
			[self updateDisplayedChannels]; /// We call this because the NSHiddenBinding of channel buttons with the above properties somehow enables
											/// the buttons when these property are set (an appkit bug IMO) even if their values don't change.
		}
	}
	int maxItems = 400;		/// 400 is close to a 384-sample plate
	NSString *itemType = @"Samples";
	if(self.showGenotypes) {
		maxItems = 1000;
		itemType = @"Genotypes";
	}
	
	/// we don't immediately load the content if the number of items to show is very large, which may take some time and block the UI
	/// The user may have selected the whole source table (of samples or genotypes) for another reason that viewing traces
	/// instead, we show a button asking for confirmation
	if(content.count < maxItems) {
		self.loadContentButton.hidden = YES;
	} else {
		self.loadContentButton.hidden = NO;
		self.loadContentButton.title = [NSString stringWithFormat:@"Show %ld %@", content.count, itemType];
		
		/// we show no content behind the button, but we need to differentiate this case from a case where no sample is selected.
		/// Otherwise, the binding machinery would see no change in content if all samples get deselected.
		/// Hence this setter won't be called and the button would still show.
		content = @[NSNull.null];
	}
	
	[self loadContentArray:content];
	
}


- (void)setShowGenotypes:(BOOL)showGenotypes {
	_showGenotypes = showGenotypes;
	if(showGenotypes) {
		/// if genotypes are shown, the detailed view columns cannot be used for sorting as they do not correspond to those of the genotype table
		/// to avoid confusing the user, we disable sorting.
		[traceOutlineView unbind:NSSortDescriptorsBinding];
		for (NSTableColumn *column in traceOutlineView.tableColumns) {
			if([column.identifier isEqualToString:@"sampleNameColumn"]) {
				/// We change the name of this column to more clearly indicate that the view shows genotypes.
				column.title = @"Genotype of";
			}
			/// We must remove the sort descriptor prototype of each column, otherwise the chevron still appears on the header
			column.sortDescriptorPrototype = nil;
		}
	} else {
		/// We re-enable sorting when the table no longer show genotypes
		/// (when it shows marker, the header is hidden anyway)
		NSDictionary *columnDescription = self.columnDescription;
		for (NSTableColumn *column in traceOutlineView.tableColumns) {
			if([column.identifier isEqualToString:@"sampleNameColumn"]) {
				column.title = @"Sample";
			}
			column.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:columnDescription[column.identifier][KeyPathToBind] ascending:YES];
		}
		[traceOutlineView bind:NSSortDescriptorsBinding
					  toObject:SampleTableController.sharedController.samples
				   withKeyPath:NSStringFromSelector(@selector(sortDescriptors)) options:nil];
		
	}
}


-(void)loadContentArray:(NSArray *)content {
	if(!content ) {
		content = NSArray.new;
	}
	
	BOOL tooMany = content.firstObject == NSNull.null;
	
	if(content.count > 0 && !tooMany) {
		self.loadContentButton.hidden = YES;
	}
	
	/// when the selection of samples/genotypes/markers to show changes, we may react to that by removing and inserting rows instead of just reloading the view
	/// so we compare the new content to the current one
	NSArray *previousContent = self.contentArray;
	
	_contentArray = content;
	
	if(tooMany) {
		content = NSArray.new;
	}
	
	/// if we show samples in separate rows, markers or genotypes (which are always one per row), we do some animation if the new contents contain items that were previously shown
	/// we don't do it if the number of items are too different between the new and previous content.
	int diffCount = abs((int)previousContent.count - (int)content.count);
	if ((self.stackMode != stackModeSamples || self.showGenotypes || self.showMarkers) && diffCount <= 10 && diffCount > 0) {
		NSIndexSet *rowsToInsert = [content indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
			return [previousContent indexOfObjectIdenticalTo:obj] == NSNotFound;  /// gets the index of samples/genotypes that were not shown previously
		}];
		
		NSIndexSet *rowsToRemove = [previousContent indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
			return [content indexOfObjectIdenticalTo:obj] == NSNotFound;
		}];
		
		NSMutableArray *remaining = [NSMutableArray arrayWithArray:previousContent];
		if(rowsToRemove.count > 0) {
			[remaining removeObjectsAtIndexes:rowsToRemove];
		}
		
		NSMutableArray *remaining2 = [NSMutableArray arrayWithArray:content];
		if(rowsToInsert.count > 0) {
			[remaining2 removeObjectsAtIndexes:rowsToInsert];
		}
		
		/// if some element(s) is/are still showing and are in the same order, we make some animation. This helps the user understand what happens
		if (rowsToRemove.count < previousContent.count && [remaining isIdenticalTo:remaining2]) {
			/// we don't animate if the number of rows to show hasn't changed (it would be more disturbing than anything)
			NSInteger animation = content.count == previousContent.count? NSTableViewAnimationEffectNone : NSTableViewAnimationEffectFade;
			
			[traceOutlineView beginUpdates];
			[traceOutlineView removeItemsAtIndexes:rowsToRemove inParent:nil withAnimation:animation];
			/// it's important to remove obsolete rows before inserting new one, and not doing the reverse
			[traceOutlineView insertItemsAtIndexes:rowsToInsert inParent:nil withAnimation:animation];
			[traceOutlineView endUpdates];
			[traceOutlineView expandItem:nil expandChildren:YES];
			[self updateHeader];
			return;
		}
	}
	[self reload];
}


/// Updates the header of the outline view as appropriate
-(void) updateHeader {
	/// we hide the header if we don't show individual (non-stacked) samples, as the normal row views (those will columns) are not shown)
	NSInteger count = self.contentArray.count;
	traceOutlineView.headerView.hidden = self.showMarkers || (self.stackMode == stackModeSamples && !self.showGenotypes && count > 1);
	self.stackedSampleTextfield.hidden = self.stackMode != stackModeSamples || self.showMarkers || self.showGenotypes || count < 2;
	if(!self.stackedSampleTextfield.hidden) {
		NSString *stringToShow = [NSString stringWithFormat:@"%ld samples stacked", count];
		if(count > 400) {
			stringToShow = [stringToShow stringByAppendingString:@" (400 shown)"];
		}
		self.stackedSampleTextfield.stringValue = stringToShow;
	}
}


/// reloads the outline view with new contents
- (void)reload {
	[traceOutlineView reloadData];
	[traceOutlineView expandItem:nil expandChildren:YES];
	[self updateHeader];
	
	/// We adjust the row height to the new content.
	float previousHeight = self.traceRowHeight;
	[self updateTraceRowHeight];
	if(previousHeight != self.traceRowHeight && traceOutlineView.numberOfRows > 0) {
		NSAnimationContext.currentContext.duration = 0;
		[NSAnimationContext beginGrouping];
		[traceOutlineView beginUpdates];
		[traceOutlineView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, traceOutlineView.numberOfRows)]];
		[traceOutlineView endUpdates];
		[NSAnimationContext endGrouping];
	}
}

-(void)loadContent:(NSButton *)sender {
	[self loadContentArray: MainWindowController.sharedController.sourceController.tableContent.selectedObjects];
}

#pragma mark - adding, removing, resizing rows


- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
	if ([item isKindOfClass: Chromatogram.class] | [item isKindOfClass: Genotype.class] ) {
		///when the element is a chromatogram or genotype, the height of the row showing its metadata is fixed
		return defaultRowHeight;
	}
	return self.traceRowHeight;
}


- (float)traceRowHeight {
	if(_traceRowHeight < minTraceRowHeight || _traceRowHeight > maxTraceRowHeight) {
		[self updateTraceRowHeight];
	}
	return _traceRowHeight;
}


- (void)setTraceRowHeight:(float)proposedHeight {
	//// It is important to use a rounded height. Otherwise, some view frames might not start/end at pixel boundaries,
	/// which results in fuzzy rendering and slightly misplaced elements
	proposedHeight = round(proposedHeight);
	if (proposedHeight < minTraceRowHeight) {
		proposedHeight = minTraceRowHeight;
	} else if(proposedHeight > maxTraceRowHeight) {
		proposedHeight = maxTraceRowHeight;
	}
	_traceRowHeight = proposedHeight;
}


/// updates the row height given the number of traces the user wants to see and the window height
- (void)updateTraceRowHeight {
	NSUInteger traceRowsPerWindow = self.numberOfRowsPerWindow;
	if(traceRowsPerWindow <= 0) {
		traceRowsPerWindow = 1;
	} else if(traceRowsPerWindow > 5) {
		traceRowsPerWindow = 5;
	}
	NSInteger numOtherRows = 0;					/// we compute the number of non-trace rows that should be visible
												///
	if(self.showGenotypes || self.stackMode == stackModeChannels) {
		/// if we show genotypes (which have just one trace) or if we stack channels, the are as numerous as trace views
		numOtherRows = traceRowsPerWindow;
	} else if((self.stackMode == stackModeSamples && self.contentArray.count > 1) || self.showMarkers) {
		numOtherRows = 0;
	} else {
		if(self.displayedChannels.count >= traceRowsPerWindow) {
			numOtherRows = 1;
		} else {
			/// if we don't stack channels, we have this estimate (we can't exactly fit all traces in this situation,
			/// as sometimes the view would show a sample row, sometimes not, depending on the scrolling position)
			numOtherRows = ceilf((float)traceRowsPerWindow / self.displayedChannels.count);
		}
	}
	
	NSInteger totRows = traceRowsPerWindow + numOtherRows;
	/// the height is computed so the number of rows fits the visible rect of the table
	self.traceRowHeight = (traceOutlineView.superview.bounds.size.height - traceOutlineView.headerView.bounds.size.height - traceOutlineView.intercellSpacing.height*totRows - numOtherRows * defaultRowHeight) / traceRowsPerWindow;
}


- (void)windowDidResize:(NSNotification *)notification {
	/// the height of trace rows must be proportional to the visible area of the view
	/// we update it during window resizing
	[self resizeRows:nil];
}


- (void)setNumberOfRowsPerWindow:(NSUInteger)numberOfRowsPerWindow {
	if(numberOfRowsPerWindow < 1) {
		numberOfRowsPerWindow = 1;
	} else if(numberOfRowsPerWindow > 5) {
		numberOfRowsPerWindow = 5;
	}
	_numberOfRowsPerWindow = numberOfRowsPerWindow;
	if(self.contentArray.count > 0) {
		[self resizeRows:self];
	}
}


///resizes the rows showing traces when the users adjusts the slider (sender) or resizes the window (sender = nil in this case)
- (IBAction)resizeRows:(id)sender {
	float currentHeight = self.traceRowHeight;
	[self updateTraceRowHeight];
	if(currentHeight == self.traceRowHeight) {
		/// when the window is resized only horizontally, the row height should not change, and it is better to return.
		/// If we don't, the pointless animation interferes with the resizing of trace views
		return;
	}
	/// This method also scrolls the table so that the position of the topmost visible row edge doesn't change
	/// If we didn't scroll, the change in row height would result in traces moving down as they get taller, or up as they get shorter, which would be disturbing, especially during window resizing.
	/// to achieve this, we count the number of traceRow above the visible rectangle
	/// we compute the difference in height due to resizing of the trace views
	
	NSRect bounds = traceOutlineView.superview.bounds;
	NSUInteger totRows = traceOutlineView.numberOfRows;
	float traceRowsAbove = 0;
	for (NSInteger row = 0; row < totRows; row++) {
		NSRect frame = [traceOutlineView rectOfRow:row];
		if(frame.origin.y >= bounds.origin.y) {
			break;
		}
		if(frame.size.height >= minTraceRowHeight -1) {
			traceRowsAbove ++;
		}
	}
	
	float traceRowHeightAbove = traceRowsAbove * currentHeight;						/// the total height they represent
	float heightDiff = traceRowsAbove  * self.traceRowHeight - traceRowHeightAbove;		/// and the difference in height after they are resized
	
	[traceOutlineView beginUpdates];
	NSAnimationContext *context = NSAnimationContext.currentContext;
	if(sender == nil) {
		context.duration = 0.0;					/// we don't animate during live resize
		context.allowsImplicitAnimation = NO;
	}
	
	[traceOutlineView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,totRows)]];
	
	if(heightDiff != 0) {
		/// we scroll the view by modifying its clipview's bounds origin (which is animatable)
		NSPoint origin = bounds.origin;
		origin.y += heightDiff;		/// this will be the new origin
		
		[NSAnimationContext beginGrouping];
		/// we scroll synchronously with the row height animation. The grouping prevents certain rows from flying around
		/// we don't use the animator proxy, as it results in jerky scrolling.
		context.allowsImplicitAnimation = sender != nil;  	/// we don't animate the scroll during window resizing.
		/// scrollToPoint: forces the scrolling to the destination even if the outline view doesn't have its final size (scrollPoint: or setBoundsOrigins: can't do that).
		[(NSClipView *)traceOutlineView.superview scrollToPoint:NSMakePoint(origin.x, origin.y)];
		[NSAnimationContext endGrouping];
	}
	[traceOutlineView endUpdates];
	
}



/// Reveals or hides rows showing particular channels.
- (void)hideChannels:(NSIndexSet*)rowsToRemove showChannels:(NSIndexSet*) rowsToInsert {
	NSInteger contentCount = self.contentArray.count;
	if (self.showGenotypes || self.showMarkers || contentCount == 0) {
		/// this is a safety measure, as this method should not be called in these situations
		return;
	}
	
	BOOL stacksSamples = self.stackMode == stackModeSamples && contentCount > 1;
	if(stacksSamples || contentCount == 1) {
		/// We animate the hiding of channels when there is only one row per channel (one sample or stacked samples).
		/// If there are more, the animation may not work well (which for me is an appkit issue) : rows move over others and do not follow the specified animation,
		/// and more importantly, some rows may have incorrect height. This is irrespective of whether the height or rows also changes and I have not found a solution.
		/// Using an NSTableView instead of an NSOutlineView doesn't solve the issue.
		[traceOutlineView beginUpdates];
		if(stacksSamples) {
			[traceOutlineView removeItemsAtIndexes:rowsToRemove inParent:nil withAnimation:NSTableViewAnimationSlideUp];
			[traceOutlineView insertItemsAtIndexes:rowsToInsert inParent:nil withAnimation:NSTableViewAnimationSlideDown];
		} else {
			Chromatogram *loneSample = self.contentArray.firstObject;
			[traceOutlineView removeItemsAtIndexes:rowsToRemove inParent:loneSample withAnimation:NSTableViewAnimationSlideUp];
			[traceOutlineView insertItemsAtIndexes:rowsToInsert inParent:loneSample withAnimation:NSTableViewAnimationSlideDown];
		}
		[self updateTraceRowHeight];
		[traceOutlineView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, traceOutlineView.numberOfRows)]];
		[traceOutlineView endUpdates];
	} else {
		/// Here, we reload the outline view, trying to maintain the position of the sample that is closest to the top of the visible rectangle.
		/// This helps users keep track of what happened.
		NSRect clipviewBounds = traceOutlineView.superview.bounds;
		NSInteger tracesRowsPerSample = (traceOutlineView.numberOfRows - contentCount)/contentCount;
		float intercellSpacing = traceOutlineView.intercellSpacing.height;
		/// We compute the number of samples that are above the visible rectangle.
		int samplesAbove = round(clipviewBounds.origin.y /(defaultRowHeight + tracesRowsPerSample * (self.traceRowHeight + intercellSpacing)));
		/// And the height of the trace rows they represent (as trace rows may be added, removed and resized due to the change)
		float totalTraceRowHeight = samplesAbove * tracesRowsPerSample * (intercellSpacing + self.traceRowHeight);
		
		[self updateTraceRowHeight];
		[traceOutlineView reloadData];
		[traceOutlineView expandItem:nil expandChildren:YES];
		tracesRowsPerSample = (traceOutlineView.numberOfRows - contentCount)/contentCount;
		
		/// We compute the difference in height of trace rows due to the change, for samples above the visible rect.
		/// We will scroll by this amount to maintain the relative position of the sample that is closest to the top of the visible rect.
		float diff = samplesAbove * tracesRowsPerSample * (self.traceRowHeight + intercellSpacing) - totalTraceRowHeight;
		
		if(diff != 0) {
			NSPoint origin = NSMakePoint(clipviewBounds.origin.x, clipviewBounds.origin.y + diff);
			/// We scroll the outline view using the method below rather than scrollPoint: or setBoundsOrigin: as these may not scroll to
			/// the desired position if the outline view hasn't yet its final size and is too short.
			[(NSClipView *)traceOutlineView.superview scrollToPoint:origin];
		}
	}
}



- (void)setStackMode:(StackMode)stackMode {
	if(self.stackMode != stackMode) {
		StackMode previous = self.stackMode;
		_stackMode = stackMode;
		if(self.contentArray && !self.showGenotypes && !self.showMarkers) {
			if(previous == stackModeSamples || stackMode == stackModeSamples || self.displayedChannels.count <= 1) {
				[self reload];
			} else {
				[self stackChannels];
			}
		}
	}
}


#pragma mark - management of colors to show


- (NSArray <NSNumber *> *)displayedChannels {
	if(!_displayedChannels) {
		[self updateDisplayedChannels];
	}
	return _displayedChannels;
}


- (void)updateDisplayedChannels {
	NSInteger nChannels = 5;
	NSMutableArray *newDisplayedChannels = [NSMutableArray arrayWithCapacity:nChannels];  /// we update the channels to display
	for (int channel = 0; channel < nChannels; channel++) {
		if ([NSUserDefaults.standardUserDefaults boolForKey:channelPreferenceKeys[channel]])
			[newDisplayedChannels addObject:@(channel)];
	}
	
	if(newDisplayedChannels.count == 0) {
		/// We impose that at least one channel is shown (even though the UI should never allow the above condition to the true).
		[NSUserDefaults.standardUserDefaults setBool:YES forKey:ShowChannel0];
		[newDisplayedChannels addObject:@0];
	}
	
	self.displayedChannels = newDisplayedChannels;
	
	for (NSButton *button in channelButtons) {
		button.enabled = !(button.state == NSControlStateValueOn && newDisplayedChannels.count == 1);
	}
}


/// message sent by buttons that show/hide channels
- (IBAction)channelsToShow:(NSButton*)sender {
	NSArray *oldDisplayedChannels = self.displayedChannels;
	/// we keep a reference of the channels previously displayed, as we make some animations inserting/removing rows when the displayed channels change
	BOOL altKeyDown = (NSApp.currentEvent.modifierFlags & NSEventModifierFlagOption) != 0;
	///if alt key is pressed, we will only show the channel associated with the button that was clicked, regardless of its previous state
	if (altKeyDown) {
		for (int channel = 0; channel <= 4; channel++) {
			[NSUserDefaults.standardUserDefaults setBool:NO forKey:channelPreferenceKeys[channel]]; /// we first deselect all channels
		}
		[NSUserDefaults.standardUserDefaults setBool:YES forKey:channelPreferenceKeys[sender.tag]]; ///and enable the channel corresponding to the button tag
	}
	[self updateDisplayedChannels];
	
	[self updateViewGivenOldDisplayedDies:oldDisplayedChannels];
}



- (void)updateViewGivenOldDisplayedDies:(NSArray *)oldDisplayedDies {
	if(self.stackMode != stackModeChannels && self.contentArray.count > 0 && !self.showMarkers && !self.showGenotypes) {
		/// if the number of item is not to high, we may hide/reveal channels with animation
		if(oldDisplayedDies.count == self.displayedChannels.count) {
			/// if the number of visible channels did not change we just reload the outline view
			[traceOutlineView reloadData];
			return;
		}
		/// else we reveal/hide rows with animation.
		/// We get the index of channels that should be hidden
		NSIndexSet *rowsToRemove = [oldDisplayedDies indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
			return ![self.displayedChannels containsObject:obj];
		}];
		
		/// We get the index of channels that should now be revealed
		NSIndexSet *rowsToInsert = [self.displayedChannels indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
			return ![oldDisplayedDies containsObject:obj];
		}];
		
		[self hideChannels:rowsToRemove showChannels:rowsToInsert]; 	///actual method that removes/inserts rows
	}
}


- (void)stackChannels { /// this stacks the visible channels of each sample in a single row or does the reverse
	if(self.stackMode == stackModeSamples || self.showGenotypes || self.showMarkers) {
		/// we should never stack channels when samples are stacked, genotypes or markers are shown
		/// (the menus or buttons for that should be disabled in this case, but this is a safety measure).
		return;
	}
	
	if(self.displayedChannels.count == 0 || self.contentArray.count > 100) {
		/// when there are many items, we just reload the table (for performance reasons)
		[self reload];
		return;
	}
	/// otherwise, we do some animation
	NSIndexSet *rowsForSeparateChannels = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, self.displayedChannels.count-1)]; ///indexes of rows that correspond to separate channels except the first one (which will hold the stacked curves)
	
	[traceOutlineView beginUpdates];
	if (self.stackMode == stackModeChannels) {
		/// Here, we stack channels in a single row per sample
		/// even if colorsToHide:colorsToReveal: calls beginUpdates, we must wrap all updates,
		/// otherwise the outline view may spawn a row view for a row that becomes visible during animation,
		/// even though this row is among those that should be removed, which creates a bug.
		/// We do it before removing other rows for better visual result
		[self hideChannels:rowsForSeparateChannels showChannels:NSIndexSet.new]; /// we remove the rows for separate channels with animation
		if(self.contentArray.count == 1) {
			[self refreshFirstRows];		/// we refresh the rows showing the stacked trace for each sample.
		}

	} else {                            		/// if we should "unstack" channels…
		[self hideChannels:NSIndexSet.new showChannels:rowsForSeparateChannels];
		if(self.contentArray.count == 1) {
			[self refreshFirstRows];
		}
	}
	[traceOutlineView endUpdates];

}

/// Reloads the content of the  first row for each sample, if visible
- (void)refreshFirstRows {
	/// We remove and reinsert the row, which refreshes it (the -reload methods won't call rowViewForRow:, so the trace view won't update).
	/// We don't just call loadContent: on the relevant trace views to reload them, because that wouldn't update the item at the row, as returned by itemAtRow: for instance.
	NSIndexSet *zero = [NSIndexSet indexSetWithIndex:0];
	if(self.displayedChannels.count > 0) {
		[traceOutlineView beginUpdates];
		for (id sample in self.contentArray) {
			[traceOutlineView removeItemsAtIndexes:zero inParent:sample withAnimation:NSTableViewAnimationEffectFade];
			[traceOutlineView insertItemsAtIndexes:zero inParent:sample withAnimation:NSTableViewAnimationEffectFade];
		}
		[traceOutlineView endUpdates];
	}
}



#pragma mark - column management

- (BOOL)canHideColumn:(NSTableColumn *)column {
	return ![column.identifier isEqualToString:@"sampleNameColumn"];
}


- (BOOL)outlineView:(NSOutlineView *)outlineView shouldReorderColumn:(NSInteger)columnIndex toColumn:(NSInteger)newColumnIndex {
	NSTableColumn *columnToMove = outlineView.tableColumns[columnIndex];
	
	if([columnToMove.identifier isEqualToString:@"sampleNameColumn"] && newColumnIndex > 0) {
		return NO;
	}
	
	if(![columnToMove.identifier isEqualToString:@"sampleNameColumn"] && newColumnIndex == 0) {
		return NO;
	}
	
	return YES;
}


- (CGFloat)outlineView:(NSOutlineView *)outlineView sizeToFitWidthOfColumn:(NSInteger)column {
	return [super tableView:outlineView sizeToFitWidthOfColumn:column];
}


#pragma mark - methods for traceViews

/// Reveals the item (sample or genotype) represented by the row of the sender in its source table.
-(void)revealInList:(NSButton *)sender {
	id itemToReveal;
	NSTableCellView *cellView = (NSTableCellView *)sender.superview;
	if(![cellView isKindOfClass:NSTableCellView.class]) {
		return;
	}
	
	if(self.showGenotypes) {
		/// In this case, the genotype to reveal is not represented by the row of the sender (it is the genotype's sample).
		/// The genotype is represented at the next row.
		NSInteger row = [traceOutlineView rowForView:cellView];
		id nextItem = [traceOutlineView itemAtRow:row+1];
		if([nextItem isKindOfClass:NSSet.class]) {
			itemToReveal = [nextItem anyObject];
		}
	} else {
		itemToReveal = cellView.objectValue;
	}
	
	if(itemToReveal) {
		[self revealItemInSourceTable:itemToReveal];
	}
}


-(void)revealItemInSourceTable:(id)itemToReveal {
	MainWindowController *mainWindowController = MainWindowController.sharedController;
	TableViewController *controller = mainWindowController.sourceController;
	mainWindowController.sourceController = controller; /// this makes sure that the genotype list is shown if needed
	[controller flashItem:itemToReveal];
}


- (void)recordReferenceRange {
	[NSUserDefaults.standardUserDefaults setFloat:referenceRange.start forKey:ReferenceStartSize];
	[NSUserDefaults.standardUserDefaults setFloat:referenceRange.start + referenceRange.len forKey:ReferenceEndSize];
}


- (BaseRange)visibleRangeForTraceView:(TraceView *)traceView {
	/// if we should synchronize visible ranges, we return the value we have recorded
	if (self.synchronizeViews && referenceRange.len > 0) {
		return  referenceRange;
	}
	
	/// else  we use the range of a view's trace, as the user would want the traces to appear where they were left
	BaseRange refRange = MakeBaseRange(-1.0, -1.0);
	for (Trace *trace in traceView.loadedTraces) {
		///if the view shows traces from different channels (hence shows a sample), we use the range of the *visible* trace with lowest channel. This creates a better visual effect when the stack channels button is pressed
		if(traceView.channel || [self.displayedChannels containsObject: @(trace.channel)]) {
			refRange = trace.visibleRange;
			break;
		}
	}
	
	if(refRange.len <= 0) {
		/// which would be the case if no trace of the view bas been displayed yet. In this case we use the defaults
		refRange = traceView.defaultRange;
	}
	return refRange;
}


- (float)topFluoLevelForTraceView:(TraceView *)traceView {
	if (self.topFluoMode == topFluoModeSynced) {
		return referenceTopFluoLevel;
	} else {
		float fluo = traceView.genotype.topFluoLevel;
		if (fluo > 0.0) {
			return fluo;
		} else {
			fluo = traceView.trace.topFluoLevel;
			if(fluo > 0.0) {
				return fluo;
			}
		}
	}
	
	return 0.0;
}


- (void)traceViewDidChangeRangeVisibleRange:(TraceView *)traceView {
	if (self.synchronizeViews && !self.showGenotypes && !self.showMarkers) {
		BaseRange range = traceView.visibleRange;
		for(TraceView *aTraceView in traceViews) {
			if(aTraceView != traceView) {
				[aTraceView setVisibleRangeAndDontNotify:range];
			}
		}
		referenceRange = range;
	}
}


- (void)traceViewDidChangeTopFluoLevel:(TraceView *)traceView{
	if (self.topFluoMode == topFluoModeSynced) {
		float fluo = traceView.topFluoLevel;
		for(TraceView *aTraceView in traceViews) {
			if(aTraceView != traceView) {
				[aTraceView setTopFluoLevelAndDontNotify:fluo];
			}
		}
		referenceTopFluoLevel = fluo;
	}
}


- (void)traceView:(TraceView *)traceView didStartMovingToRange:(BaseRange)range {
	if (!self.showGenotypes && !self.showMarkers && self.topFluoMode == topFluoModeHighestPeak && self.synchronizeViews ) {
		/// if a view starts moving , if sync is on and if traceViews auto scale of their highest peak,
		/// we animate the vertical scale so that it changes during the move (and not after)
		for(TraceView *aTraceView in traceViews) {
			if(aTraceView != traceView) {
				float targetFluo = [aTraceView topFluoForRange:range];
				if(targetFluo > 0) {
					aTraceView.animator.topFluoLevel = targetFluo;
				}
			}
		}
	}
}


- (void)traceView:(TraceView *)traceView didClickTrace:(Trace *)trace {
	id itemToReveal = nil;
	if(self.showGenotypes) {
		itemToReveal = [trace.chromatogram genotypeForMarker:traceView.marker];
	} else {
		itemToReveal = trace.chromatogram;
	}
	if(itemToReveal) {
		[self revealItemInSourceTable:itemToReveal];
	}
}


- (void)setTopFluoMode:(TopFluoMode)topFluoMode {
	_topFluoMode = topFluoMode;
	self.autoScaleToHighestPeak = topFluoMode == topFluoModeHighestPeak;
}


- (void)setDefaultStartSize:(float)defaultStartSize {
	_defaultStartSize = defaultStartSize;
	self.defaultRange = MakeBaseRange(defaultStartSize, self.defaultEndSize-defaultStartSize);
}


- (void)setDefaultEndSize:(float)defaultEndSize {
	_defaultEndSize = defaultEndSize;
	self.defaultRange = MakeBaseRange(self.defaultStartSize, defaultEndSize-self.defaultStartSize);
}


- (void)menuNeedsUpdate:(NSMenu *)menu {
	if([menu.identifier isEqualToString:applySizeStandardMenuIdentifier]) {
		NSMenuItem *firstItem = menu.itemArray.firstObject;
		if(firstItem) {
			[menu removeAllItems];
			[menu addItem:firstItem];
			for(SizeStandard *standard in SizeStandardTableController.sharedController.tableContent.arrangedObjects) {
				NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:standard.name action:@selector(applySizeStandard:) keyEquivalent:@""];
				item.target = self;
				item.representedObject = standard;
				[menu addItem:item];
			}
		}
	} else {
		[super menuNeedsUpdate:menu];
	}
}


-(IBAction)applySizeStandard:(NSMenuItem *)sender {
	SizeStandard *standard = sender.representedObject;
	if(standard) {
		TraceView *traceView = sender.menu.itemArray.firstObject.representedObject;
		if([traceView respondsToSelector:@selector(loadedTraces)]) {
			NSArray *samples = [traceView.loadedTraces valueForKeyPath:@"@distinctUnionOfObjects.chromatogram"];
			if(samples.count > 0) {
                if(samples.count > 1 && self.stackMode == stackModeSamples && samples.count < _contentArray.count) {
                    samples = self.contentArray;
                }
				[SampleTableController.sharedController applySizeStandard:standard toSamples:samples];
			}
		}
	}
}

# pragma mark -other

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if(menuItem.action == @selector(moveSelectionByStep:)) {
		return [MainWindowController.sharedController.sourceController validateMenuItem:menuItem];
	}
	return [super validateMenuItem:menuItem];
}


- (void)moveSelectionByStep:(id)sender {
	[MainWindowController.sharedController.sourceController moveSelectionByStep:sender];
}


- (void)dealloc {
	[NSApp removeObserver:self forKeyPath:NSStringFromSelector(@selector(effectiveAppearance))];
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

@end

