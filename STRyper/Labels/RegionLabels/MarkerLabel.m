//
//  MarkerLabel.m
//  STRyper
//
//  Created by Jean Peccoud on 25/03/2023.
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


#import "MarkerLabel.h"
#import "TraceView.h"
#import "MarkerView.h"
#import "Mmarker.h"
#import "RulerView.h"
#import "Bin.h"
#import "NewMarkerPopover.h"

static NSPopover *addBinsPopover;	/// The popover that permits to define the set of bins to add to the marker
									
static NewMarkerPopover *newMarkerPopover;	/// The popover that permits to define a new marker


/// The tag used to identify the controls in the addBinsPopover
/// these tags are defined in IB
enum addBinPopoverTag : NSInteger {
	binStartTextFieldTag = 4,
	binEndTextFieldTag = 5,
	addBinSetCancelButtonTag = 6,
	addBinsButtonTag = 7,
	binWidthSliderTag = 8,
	binSpacingButtonTag = 9
} addBinPopoverTag;


@implementation MarkerLabel {
	/// As these labels are not drawn in the trace view (their "view" property is the marker view), it is useful to keep a reference to the traceView
	__weak TraceView *traceView;
	
	CALayer *editButtonLayer;	/// the layer symbolizing the button that can be clicked to popup the menu (or lock the marker)
								/// It is more convenient than using an NSButton because we make it a sublayer of our layer
	NSTrackingArea *editButtonArea; /// A tracking area to determine if the edit button is hovered
	NSToolTipTag toolTipTag;		/// a tag for a tooltip indicating the edit button role
	BOOL hoveredEditButton;			/// Whether the edit button is hovered

}

/// Images for the edit button. CALayer cannot adapt to the app appearance if it uses an NSImage, so we have to specify different images for light and dark mode
/// We also have difference images for when the button is hovered or not and depending on the marker edit state
static NSImage *actionRoundImage, *actionRoundHoveredImage, *actionCheckImage, *actionCheckHoveredImage,
*actionRoundDarkImage, *actionRoundHoveredDarkImage, *actionCheckDarkImage, *actionCheckHoveredDarkImage;

# pragma mark - attributes and appearance

+ (void)initialize {
	actionCheckHoveredImage = [NSImage imageNamed:@"action check hovered"];
	actionRoundHoveredImage = [NSImage imageNamed:@"action round hovered"];
	actionCheckImage = [NSImage imageNamed:@"action check"];
	actionRoundImage = [NSImage imageNamed:@"action round"];
}


- (BOOL)isMarkerLabel {
	return YES;
}


- (instancetype)init
{
	self = [super init];
	if (self) {
		_offset = MarkerOffsetNone;
		
		layer = CALayer.new;
		layer.delegate = self;
		
		bandLayer = CALayer.new;
		bandLayer.delegate = self;
		stringLayer = CATextLayer.new;
		stringLayer.delegate = self;
		stringLayer.drawsAsynchronously = YES;  			/// maybe that helps a bit (not noticeable)
		stringLayer.font = (__bridge CFTypeRef _Nullable)([NSFont labelFontOfSize:10.0]);
		stringLayer.foregroundColor = NSColor.textColor.CGColor;
		stringLayer.allowsFontSubpixelQuantization = YES;
		stringLayer.contentsScale = 2.0;
		
		layer.zPosition = 0.0;
		layer.masksToBounds = YES;			/// the marker's name is clipped by the layer to avoid overlapping between marker names
		[layer addSublayer:stringLayer];
		layer.borderColor = NSColor.grayColor.CGColor; /// this makes edge visible in dark mode.
		layer.bounds = CGRectMake(0, -3, 50, 20);
		/// we use -3 because we place the layer bottom edge 3 points below the view, so as to hide the bottom edge of the border when it is highlighted.
		
		stringLayer.anchorPoint = CGPointMake(0,0);
		stringLayer.fontSize = 10.0;
		[layer addSublayer:bandLayer];
		editButtonLayer = CALayer.new;
		editButtonLayer.delegate = self;
		editButtonLayer.anchorPoint = CGPointMake(0, 0);
		
		editButtonLayer.bounds = CGRectMake(0, 0, 15, 15);
		[layer addSublayer:editButtonLayer];
		disabledColor = [NSColor colorWithCalibratedWhite:0.8 alpha:1.0];
		edgeColor = NSColor.grayColor;
	}
	return self;
}



- (void)setView:(TraceView *)view {
	super.view = view;
	if(layer && view) {
		[view.layer addSublayer:layer];
		traceView = ((MarkerView *)view).traceView;
		NSInteger color = view.channel;		/// the color should depend on the region rather than on the view. TO IMPROVE
											/// at this stage, the region is not set, and the colors are define by the trace view
		NSColor *markerColor = traceView.colorsForChannels[color];
		
		/// We use a horizontal segment to represent the marker range. The color is based on the channel, but a bit brighter
		bandColor = [markerColor blendedColorWithFraction:0.2 ofColor:NSColor.whiteColor];
		
		defaultColor = defaultColor = self.enabled? bandColor : [NSColor colorWithCalibratedWhite:0.8 alpha:1.0];
		
		/// The color is even brighter when the label is hovered
		hoveredColor = [markerColor blendedColorWithFraction:0.5 ofColor:NSColor.whiteColor];
		activeColor = markerColor;
	}
}


- (void)updateAppearance {
	[super updateAppearance];
	if(editButtonLayer) {
		EditState editState = self.editState;
		BOOL wasHidden = editButtonLayer.hidden;
		editButtonLayer.hidden = (editState == editStateNil && !self.hovered && !self.highlighted) || !self.enabled || !self.region;
		[self updateEditButton];

		if(wasHidden != editButtonLayer.hidden) {
			/// we reposition the label internal layers as the button layer's change in visibility changes the name's position
			[self layoutInternalLayers];
		}
	}
}


- (void)updateForTheme {
	[super updateForTheme];
	[self setEditButtonContent];
}


-(void) updateEditButton {
	/// Since the edit button uses an image that has a dark appearance, it's content must be set within -updateLayer of the host view
	self.view.needsUpdateLabelAppearance = YES;
}


-(void)setEditButtonContent {
	if(editButtonLayer) {
		NSImage *buttonImage;
		BOOL inEdit = self.editState != editStateNil;
		if(hoveredEditButton) {
			buttonImage = inEdit? actionCheckHoveredImage : actionRoundHoveredImage;
		} else {
			buttonImage = inEdit? actionCheckImage : actionRoundImage;
		}
		if(buttonImage) {
			editButtonLayer.contents = (__bridge id _Nullable)([buttonImage CGImageForProposedRect:nil context:nil hints:nil]);
		}
	}
}

# pragma mark - user events

- (void)mouseEntered:(NSEvent *)theEvent {
	[super mouseEntered:theEvent];
	if(theEvent.trackingArea == editButtonArea) {
		hoveredEditButton = YES;
		[self updateAppearance];
	}
}


- (void)mouseExited:(NSEvent *)theEvent {
	[super mouseExited:theEvent];
	if(theEvent.trackingArea == editButtonArea) {
		hoveredEditButton = NO;
		[self updateAppearance];
	}
}


- (void)mouseUpInView {
	[super mouseUpInView];
	if(self.highlighted) {
		/// we detect if the user has clicked the edit button
		if(editButtonLayer && !editButtonLayer.hidden) {
			NSPoint mouseUpPoint = [layer convertPoint:self.view.mouseUpPoint fromLayer:self.view.layer];
			if(NSPointInRect(mouseUpPoint, editButtonLayer.frame)) {
				Mmarker *marker = (Mmarker*)self.region;
				if(self.editState != editStateNil) {		/// if true, the edit button looks like a checkbox
					marker.editState = editStateNil;		/// in which case, clicking it exits the edit state of the marker (and all its labels)
				} else {
					[self.menu popUpMenuPositioningItem:nil atLocation:self.view.mouseUpPoint inView:self.view];
				}
			}
		}
	}
}

# pragma mark - geometry and tracking areas

- (void)reposition {
	TraceView *view = self.view;
	float hScale = view.hScale;
	if(hScale <= 0 || self.hidden) {
		return;
	}
	
	float startSize = self.startSize;
	float endSize = self.endSize;
	float startX = [self.view xForSize:startSize];     /// to get our frame, we convert our position in base pairs to points (x coordinates)
	regionRect = NSMakeRect(startX, 0, (endSize - startSize) * hScale, NSMaxY(self.view.bounds));
	
	if(self.highlighted) {
		/// when highlighted, our frame (used by the tracking area) gets a bit wider so that the user can more easily click an edge to resize us
		self.frame = NSInsetRect(regionRect, -2, 0);
	} else {
		self.frame = regionRect;
	}
	
	/// the rectangle representing our marker is a 3-point high bar
	regionRect.size.height = 3;
	
	/// if the label is not in the view's bounds (with some 2-point margin) and wasn't previously, we don't need to update the layer. The label isn't visible
	NSRect intersection = NSIntersectionRect(regionRect, NSInsetRect(self.view.bounds, -2, 0));
	if(intersection.size.width <= 0.1 && !CGRectIntersectsRect(layer.frame, layer.superlayer.bounds)) {
		return;
	}
	/// to avoid drawing a layer that is very large (at very high hScale), we won't draw what is not visible
	if(intersection.size.width > 0) {
		regionRect = intersection;
	} else {
		/// if the label is not visible, we don't use the intersection rect (which is NSZeroRect) as it doesn't correspond to the label's start
		/// If we did, this may make the label move to the left
		regionRect.size.width = 1;
	}
	
	layer.frame = CGRectMake(regionRect.origin.x, -3, regionRect.size.width, self.frame.size.height + 3);
	bandLayer.frame = CGRectMake(0, 0, regionRect.size.width, regionRect.size.height);
	
	[self layoutInternalLayers];
	
	/// if we show a popover, we move it in sync with the label (the markerView doesn't scroll).
	if(attachedPopover) {
		attachedPopover.positioningRect = self.frame;
	}
	
	if(!traceView.isMoving && self.enabled && !self.dragged) {
		[self updateTrackingArea];  
	}
}

-(void)layoutInternalLayers {
	/// We don't do that in -layoutSublayersOfLayer: because it would be difficult to know if sublayers should be positioned with animation.
	/// The -animated property of the label may not be appropriate when that method is called
	
	/// The name is at the middle of the part of the marker label that is visible (and not behind the navigation buttons)
	NSRect visibleMarkerRect = NSIntersectionRect(regionRect, NSMakeRect(0, 0, NSMaxX(self.view.bounds)-15, NSMaxY(self.view.bounds)));
	CGPoint position = CGPointMake(NSMidX(visibleMarkerRect) - regionRect.origin.x - NSMidX(stringLayer.bounds), 3);
	if(!editButtonLayer.hidden) {
		position.x -= editButtonLayer.bounds.size.width/2 - 0.5;
		if(position.x < 1) {
			position.x = 1;		/// makes sure the button is visible even if the label is very short
		}
	}
	/// we position the button even if hidden. Otherwise, it may arrive from a distance when we get hovered
	editButtonLayer.position = position;

	stringLayer.position = editButtonLayer.hidden? CGPointMake(position.x, 4) : CGPointMake(NSMaxX(editButtonLayer.frame) + 1, 4);
	
	if(!traceView.isMoving && !self.dragged) {
		[self updateButtonArea];
	}
}


- (void)updateTrackingArea {
	[super updateTrackingArea];
	[self updateButtonArea];
}


-(void) updateButtonArea {
	TraceView *view = self.view;
	if (editButtonArea) {
		[view removeTrackingArea:editButtonArea];
		[view removeToolTip:toolTipTag];
		editButtonArea = nil;
	}
	if(!editButtonLayer.hidden) {
		NSRect buttonFrame = [editButtonLayer convertRect:editButtonLayer.bounds toLayer:view.layer];
		editButtonArea = [self addTrackingAreaForRect:buttonFrame];
		toolTipTag = [view addToolTipRect:buttonFrame owner:self userData:nil];
	}
}



-(void)setFrame:(NSRect)frame {
	_frame = frame;
}


# pragma mark - menu and actions

- (NSString *)description {
	/// This describes what the edit button does
	if(self.editState == editStateNil) {
		return @"Show options";
	} else {
		return @"End editing";
	}
}

- (NSMenu *)menu {
	_menu = super.menu;
	if(_menu.itemArray.count < 4) {
		[_menu addItemWithTitle:@"Zoom to Marker" action:@selector(zoom:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:@"loupeBadge"]];
		[_menu addItem:NSMenuItem.separatorItem];
		[_menu addItemWithTitle:@"Generate Bins" action:@selector(spawnAddBinsPopover:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:@"binset"]];
		[_menu addItemWithTitle:@"Edit Bins" action:@selector(setEditStateFromMenuItem:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:@"edit bins"]];
		[_menu.itemArray.lastObject setTag:editStateBins];
		[_menu addItemWithTitle:@"Move Bins" action:@selector(setEditStateFromMenuItem:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:@"move bins"]];
		[_menu.itemArray.lastObject setTag:editStateBinSet];
		[_menu addItem:NSMenuItem.separatorItem];
		[_menu addItemWithTitle:@"Adjust Offset" action:nil keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:@"marker offset"]];
		/// we make a submenu which allows specifying the target samples of the action
		NSMenu *submenu = NSMenu.new;
		[submenu addItemWithTitle:@"Apply to:" action:nil keyEquivalent:@""];
		[submenu addItemWithTitle:@"Sample(s) at this row" action:@selector(setEditStateFromMenuItem:) keyEquivalent:@""];
		[submenu addItemWithTitle:@"Samples of this run in the selected folder" action:@selector(setEditStateFromMenuItem:) keyEquivalent:@""];
		[submenu addItemWithTitle:@"All samples of the folder" action:@selector(setEditStateFromMenuItem:) keyEquivalent:@""];
		EditState j = editStateShownSamples;
		for(NSMenuItem *anItem in submenu.itemArray) {
			if(anItem.action) {
				anItem.target = self;
				anItem.tag = j;
				j++;
			}
		}
		[_menu.itemArray.lastObject setSubmenu:submenu];
		
		[_menu addItemWithTitle:@"Reset Offset" action:nil keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:@"reset"]];
		submenu = submenu.copy;			/// this action has an equivalent submenu as the previous action

		for(NSMenuItem *anItem in submenu.itemArray) {
			if(anItem.action) {
				anItem.action = @selector(resetOffset:);
			}
		}
		[_menu.itemArray.lastObject setSubmenu:submenu];

		for(NSMenuItem *item in self.menu.itemArray) {
			if(!item.submenu) {
				item.target = self;
			}
		}
		_menu.delegate = self;
	}
	return _menu;
}


- (void)menuNeedsUpdate:(NSMenu *)menu {
	BOOL hide = traceView.loadedTraces.count == 0 || self.editState != editStateNil;
	for(NSMenuItem *item in menu.itemArray) {
		if(item.submenu) {
			/// the items that have submenus all allow action that are not relevant when the traceView doesn't show samples (but only a marker)
			/// we don't show them either when we are already in an edit state
			item.hidden = hide;
		}
	}
}


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	BOOL valid = YES;
	NSInteger tag = menuItem.tag;
	if(tag != editStateNil && self.editState != editStateNil) {
		/// if we are already in an edit state, we disable any item that sets an edit state
		valid = NO;
	} else if (tag == editStateBinSet) {
		/// if the target is the bin set, we check if the marker indeed has bins
		Mmarker *marker = self.region;
		valid = marker.bins.count > 0;		/// if there is no bin set, we disable the menu that allows to move it
	}
	menuItem.hidden = !valid;
	return valid;
	
}



- (void)zoom:(id)sender {
	[traceView zoomToMarkerLabel:self];
}


-(void)resetOffset:(NSMenuItem *)sender {
	[self _updateTargetSamples:sender.tag withOffset:MarkerOffsetNone];
}

/// Sets our edit state depending on the tag of the menu item sending this message
-(void)setEditStateFromMenuItem:(NSMenuItem *)sender {
	NSInteger tag = sender.tag;
	Mmarker *marker = self.region;
	if(tag <= editStateBins) {
		/// We transfer the edit state to our marker, hence to all labels representing it (via KVO)
		marker.editState = tag;
	} else {
		/// Otherwise, the state relates to an offset that is specific to target samples (and not to the marker in general)
		/// all labels representing the marker should end their edit state (otherwise, the user may get confused about the various states of enabled labels)
		/// This is a safety measure, as the menu items allowing to enter an edit states are disabled if the marker is already in an edit state
		marker.editState = editStateNil;
		
		self.editState = tag;
		/// the state is transferred to the label showing the marker on the trace view, as it is this label that defines the UI allowing offset editing
		for (RegionLabel *label in traceView.markerLabels) {
			if(label.region == marker) {
				label.editState = tag;
				break;
			}
		}
	}
	if(tag != editStateNil) {
		/// only one marker per view at a time can be in an edit state
		for(Mmarker *aMarker in [marker.panel markersForChannel:marker.channel]) {
			if(aMarker != marker) {
				aMarker.editState = editStateNil;
			}
		}
	}
}


- (void)setEditState:(EditState)editState {
	if(editState != self.editState) {
		super.editState = editState;
		/// the edit state is only reflected in the icon shown by the edit button.
		[self updateAppearance];
		[self.view labelDidChangeEditState:self];
	}
}
	

- (void)spawnRegionPopover:(id)sender {
	Mmarker *marker = self.region;
	if(marker.objectID.isTemporaryID) {
		if(!newMarkerPopover) {
			newMarkerPopover = NewMarkerPopover.popover;
			newMarkerPopover.behavior = NSPopoverBehaviorTransient;
			newMarkerPopover.markerChannelPopupButton.enabled = NO;
			newMarkerPopover.okAction = @selector(addMarker:);
			newMarkerPopover.cancelAction = @selector(cancelAddMarker:);
		}
		newMarkerPopover.markerChannel = self.view.channel;
		newMarkerPopover.markerStart = marker.start;
		newMarkerPopover.markerEnd = marker.end;
		if(newMarkerPopover.delegate != self) {
			[newMarkerPopover.markerNameTextField bind:NSValueBinding toObject:marker withKeyPath:@"name" options:nil];
			newMarkerPopover.okActionTarget = self;
			newMarkerPopover.cancelActionTarget = self;
			newMarkerPopover.markerStartTextField.delegate = (id)self;
			newMarkerPopover.markerEndTextField.delegate = (id)self;
			newMarkerPopover.delegate = (id)self;
		}
		[newMarkerPopover showRelativeToRect:self.frame ofView:self.view preferredEdge:NSMaxYEdge modal:YES];
	} else {
		[super spawnRegionPopover:sender];
	}
}



- (BOOL)popoverShouldClose:(NSPopover *)popover {
	if(popover == newMarkerPopover) {
		return NO;
	}
	return [super popoverShouldClose:popover];
}




-(void)cancelAddMarker:(id) sender {
	[newMarkerPopover close];
	Region *region = self.region;
	[self.region.managedObjectContext deleteObject:region];
	[(MarkerView *)self.view updateContent];

}



-(void)addMarker:(NSButton *) sender {
	[sender.window makeFirstResponder:nil];	/// this forces the fields of the popover to validate
	Mmarker *marker = self.region;
	marker.ploidy = newMarkerPopover.diploid + 1;
	NSError *error;
	[marker validateForUpdate:&error];
	if(error) {
		NSArray *errors = (error.userInfo)[NSDetailedErrorsKey];
		if(errors.count > 1) {
			error = errors.firstObject;
		}
		
		[NSApp presentError:error];
		return;
	}
	[self.view labelDidUpdateNewRegion:self];
	[newMarkerPopover close];
}




-(void)spawnAddBinsPopover:(NSMenuItem *)sender {
	if(!addBinsPopover) {
		addBinsPopover = NSPopover.new;
		NSViewController *controller = [[NSViewController alloc] initWithNibName:@"AutoBinPopover" bundle:nil];
		addBinsPopover.contentViewController = controller;
		addBinsPopover.behavior = NSPopoverBehaviorSemitransient;
		NSButton *cancelButton = [controller.view viewWithTag:addBinSetCancelButtonTag];
		cancelButton.action = @selector(close);
		cancelButton.target = addBinsPopover;
		NSPopUpButton *binSpacingButton = [controller.view viewWithTag:binSpacingButtonTag];
		[binSpacingButton selectItemAtIndex:1];

	}
	NSView *view = addBinsPopover.contentViewController.view;
	addBinsPopover.delegate = self;
	NSTextField *startBinTextField = [view viewWithTag:binStartTextFieldTag];
	startBinTextField.intValue = round(self.region.start + 0.5) +1;
	startBinTextField.delegate = (id)self;
	NSTextField *endBinTextfield = [view viewWithTag:binEndTextFieldTag];
	endBinTextfield.intValue = (int)self.region.end -1;
	endBinTextfield.delegate = (id)self;
	NSButton *addBinsButton = [view viewWithTag:addBinsButtonTag];
	addBinsButton.target = self;
	addBinsButton.action = @selector(addBinSet:);

	[addBinsPopover showRelativeToRect:self.frame ofView:self.view preferredEdge:NSMaxYEdge];

}


- (void)controlTextDidEndEditing:(NSNotification *)obj {
	NSTextField *textField = obj.object;
	NSInteger tag = textField.tag;
	if(tag == binEndTextFieldTag || tag == binStartTextFieldTag) {
		/// we ensure that value entered in these textfields are consistent
		NSSlider *binWidthSlider = [textField.superview viewWithTag:binWidthSliderTag];
		float halfBinWidth = binWidthSlider.floatValue/2;

		float value = textField.floatValue;
		/// we make sure that the value for the bin set is within the range of the marker
		float regionStart = self.region.start + 0.1;
		float regionEnd = self.region.end - 0.1;
		if(value - halfBinWidth < regionStart) {
			value = regionStart + halfBinWidth;
		} else if(value + halfBinWidth > regionEnd) {
			value = regionEnd - halfBinWidth;
		}
		
		/// we make sure that the value for the start of the bin set does not exceed the value entered for the end of the bin set (and vice versa)
		if(tag == binStartTextFieldTag) {
			NSTextField *otherTextField = [textField.superview viewWithTag: binEndTextFieldTag];
			float otherValue = otherTextField.floatValue;
			if(value > otherValue) {
				value = otherValue;
			}
		}
		
		if(tag == binEndTextFieldTag) {
			NSTextField *otherTextField = [textField.superview viewWithTag: binStartTextFieldTag];
			float otherValue = otherTextField.floatValue;
			if(value < otherValue) {
				value = otherValue;
			}
		}
		
		textField.floatValue = value;
	} else [super controlTextDidEndEditing:obj];
}


/// Adds a set of bins to our marker based on specifications defined by the user on the popover (to which the sender belongs)
-(void)addBinSet:(NSButton *)sender {
	NSView *view = addBinsPopover.contentViewController.view;
	NSTextField *startBinTextField = [view viewWithTag:binStartTextFieldTag];
	NSTextField *endBinTextfield = [view viewWithTag:binEndTextFieldTag];
	NSSlider *binWidthSlider = [view viewWithTag:binWidthSliderTag];
	NSPopUpButton *binSpacingButton = [view viewWithTag:binSpacingButtonTag];
	Mmarker *marker = self.region;
	if(!marker || !startBinTextField || !endBinTextfield || !binWidthSlider || !binSpacingButton) {
		return;
	}
	
	float binSetStart = startBinTextField.floatValue;
	float binSetEnd = endBinTextfield.floatValue;
	float binWidth = binWidthSlider.floatValue;
	if(binWidth < 0.5) {
		binWidth = 0.5;
	} else if(binWidth > 1.5) {
		binWidth = 1.5;
	}
	
	NSInteger binSpacing = binSpacingButton.indexOfSelectedItem + 1;
	if(binSpacing < 1) {
		binSpacing = 1;
	}
	
	if(binWidth >= binSpacing) {
		binWidth = binSpacing - 0.1;
	}
	
	float markerStart = marker.start + 0.1;
	float markerEnd = marker.end - 0.1;
	NSMutableSet *bins = NSMutableSet.new;
	for(float i = binSetStart; i <= binSetEnd; i+= binSpacing) {
		float binStart = i - binWidth/2;
		float binEnd = i + binWidth/2;
		if(binStart >= markerStart && binEnd < markerEnd) {
			Bin *newBin = [[Bin alloc] initWithContext:self.region.managedObjectContext];
			newBin.start = binStart;
			newBin.end = binEnd;
			[newBin autoName];
			[bins addObject:newBin];
		}
	}
	
	if(bins.count > 0) {
		[addBinsPopover close];
		NSUndoManager *undoManager = marker.managedObjectContext.undoManager;
			[undoManager setActionName:@"Generate Bins"];
		marker.bins = [NSSet setWithSet:bins];
		
		/// we allow the user to move the new bin set (which also forces to show bins regardless of the showBins property of the view)
		marker.editState = editStateBinSet;
		
		/// if the user undoes the addition of bins, it makes sense to exit the edit state.
		[undoManager registerUndoWithTarget:self selector:@selector(exitBinSetEditState) object:nil];

	} else {
		NSError *error = [NSError errorWithDescription:@"No bin was added because the marker is too narrow." suggestion:@"You may widen the marker."];
		[[NSAlert alertWithError:error] beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
		}];
	}
}


-(void)exitBinSetEditState {
	Mmarker *marker = self.region;
	if(marker.editState == editStateBinSet) {
		[self.region setEditState:editStateNil];
	}
}


- (void)doubleClickAction:(id)sender {
	/// when double-clicked, we show the popover that allows the user to edit our name, start and end positions
	NSPoint mouseUpPoint = [layer convertPoint:self.view.mouseUpPoint fromLayer:self.view.layer];
	if(!NSPointInRect(mouseUpPoint, editButtonLayer.frame)) {
		/// we don't show the popover if the double click happened on the edit button
		[self spawnRegionPopover:sender];
	}
}





@end
