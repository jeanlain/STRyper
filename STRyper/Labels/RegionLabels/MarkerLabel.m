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
#import "Bin.h"
#import "NewMarkerPopover.h"

static NSPopover *addBinsPopover;	/// The popover that permits to define the set of bins to add to the marker
									
static NewMarkerPopover *newMarkerPopover;	/// The popover that permits to define a new marker


@implementation MarkerLabel {
	/// As these labels are not drawn in the trace view (their "view" property is the marker view), it is useful to keep a reference to the traceView
	__weak TraceView *traceView;
	
	ChannelNumber channel;
	NSColor *disabledColor, *hoveredColor, *defaultColor;
	
	CALayer *actionButtonLayer;	/// the layer symbolizing the button that can be clicked to popup the menu (or end editing)
								/// It is more convenient than using an NSButton because we make it a sublayer of our layer
	__weak NSTrackingArea *actionButtonArea; /// A tracking area to determine if the action button is hovered
	NSToolTipTag toolTipTag;		/// a tag for a tooltip indicating the action button role
	BOOL hoveredActionButton;			/// Whether the action button is hovered

}

/// Images for the action button. CALayer cannot adapt to the app appearance if it uses an NSImage, so we have to specify different images for light and dark mode
/// We also have difference images for when the button is hovered or not and depending on the marker edit state
static NSImage *actionRoundImage, *actionRoundHoveredImage, *actionCheckImage, *actionCheckHoveredImage,
*actionRoundDarkImage, *actionRoundHoveredDarkImage, *actionCheckDarkImage, *actionCheckHoveredDarkImage;

# pragma mark - attributes and appearance

+ (void)initialize {
	if([self class] == MarkerLabel.class) {
		actionCheckHoveredImage = [NSImage imageNamed:@"action check hovered"];
		actionRoundHoveredImage = [NSImage imageNamed:@"action round hovered"];
		actionCheckImage = [NSImage imageNamed:@"action check"];
		actionRoundImage = [NSImage imageNamed:@"action round"];
	}
}


- (BOOL)isMarkerLabel {
	return YES;
}


- (instancetype)init
{
	self = [super init];
	if (self) {
		_offset = MarkerOffsetNone;
		channel = -1;
		
		layer = CALayer.new;
		layer.delegate = self;
		layer.actions = @{NSStringFromSelector(@selector(borderWidth)):NSNull.null};
		layer.opaque = YES;
		
		bandLayer = CALayer.new;
		bandLayer.actions = @{NSStringFromSelector(@selector(backgroundColor)):NSNull.null};
	
		bandLayer.delegate = self;
		stringLayer = CATextLayer.new;
		stringLayer.delegate = self;
		stringLayer.actions = @{@"contents":NSNull.null};
		stringLayer.drawsAsynchronously = YES;  			/// maybe that helps a bit (not noticeable)
		stringLayer.font = (__bridge CFTypeRef _Nullable)([NSFont labelFontOfSize:10.0]);
		stringLayer.foregroundColor = NSColor.textColor.CGColor;
		stringLayer.allowsFontSubpixelQuantization = YES;
		stringLayer.contentsScale = 2.0;
		
		layer.zPosition = 0.0;
		layer.masksToBounds = YES;			/// the marker's name is clipped by the layer to avoid overlapping between marker names
		[layer addSublayer:stringLayer];
		layer.borderColor = NSColor.grayColor.CGColor; 
		layer.bounds = CGRectMake(0, -3, 50, 20);
		/// we use -3 because we place the layer bottom edge 3 points below the view, so as to hide the bottom edge of the border when it is highlighted.
		
		stringLayer.anchorPoint = CGPointMake(0,0);
		stringLayer.fontSize = 10.0;
		[layer addSublayer:bandLayer];
		actionButtonLayer = CALayer.new;
		actionButtonLayer.hidden = YES;
		actionButtonLayer.actions = @{NSStringFromSelector(@selector(contents)): NSNull.null};
		actionButtonLayer.delegate = self;
		actionButtonLayer.anchorPoint = CGPointMake(0, 0);
		actionButtonLayer.bounds = CGRectMake(0, 0, 15, 15);
		[layer addSublayer:actionButtonLayer];
		
		disabledColor = [NSColor colorWithCalibratedWhite:0.8 alpha:1.0];
	}
	return self;
}


- (void)setRegion:(__kindof Region *)region {
	super.region = region;
	ChannelNumber regionChannel = ((Mmarker *)region).channel;
	if(channel != regionChannel) {
		channel = regionChannel;
		/// We use a horizontal segment to represent the marker range. The color is based on the channel, but a bit brighter
		defaultColor = LabelView.colorsForChannels[channel];
		
		bandLayer.backgroundColor = self.enabled? defaultColor.CGColor : disabledColor.CGColor;
		
		/// The color is brighter when the label is hovered
		hoveredColor = [defaultColor blendedColorWithFraction:0.4 ofColor:NSColor.whiteColor];
	}
}



- (void)setView:(TraceView *)view {
	super.view = view;
	if(layer && view) {
		[view.backgroundLayer addSublayer:layer];
		traceView = ((MarkerView *)view).traceView;
	}
}


- (void)updateAppearance {
	[super updateAppearance];
	if(self.hovered || self.highlighted) {
		bandLayer.backgroundColor = hoveredColor.CGColor;
	} else {
		bandLayer.backgroundColor = self.enabled ? defaultColor.CGColor : disabledColor.CGColor;
	}
	
	if(actionButtonLayer) {
		EditState editState = self.editState;
		BOOL wasHidden = actionButtonLayer.hidden;
		actionButtonLayer.hidden = (editState == editStateNil && !self.hovered && !self.highlighted) || !self.enabled || !self.region;
		[self updateActionButton];

		if(wasHidden != actionButtonLayer.hidden) {
			/// we reposition the label internal layers as the button layer's change in visibility changes the name's position
			[self layoutInternalLayers];
		}
	}
}


- (void)updateForTheme {
	[super updateForTheme];
	[self setActionButtonContent];
}


-(void) updateActionButton {
	/// Since the action button uses an image that has a dark appearance, it's content must be set within -updateLayer of the host view
	self.view.needsUpdateLabelAppearance = YES;
}


-(void)setActionButtonContent {
	if(actionButtonLayer) {
		NSImage *buttonImage;
		BOOL inEdit = self.editState != editStateNil;
		if(hoveredActionButton) {
			buttonImage = inEdit? actionCheckHoveredImage : actionRoundHoveredImage;
		} else {
			buttonImage = inEdit? actionCheckImage : actionRoundImage;
		}
		if(buttonImage) {
			actionButtonLayer.contents = (__bridge id _Nullable)([buttonImage CGImageForProposedRect:nil context:nil hints:nil]);
		}
	}
}

# pragma mark - user events

- (void)mouseEntered:(NSEvent *)theEvent {
	[super mouseEntered:theEvent];
	if(theEvent.trackingArea == actionButtonArea) {
		hoveredActionButton = YES;
		[self updateAppearance];
	}
}


- (void)mouseExited:(NSEvent *)theEvent {
	[super mouseExited:theEvent];
	if(theEvent.trackingArea == actionButtonArea) {
		hoveredActionButton = NO;
		[self updateAppearance];
	}
}


- (void)mouseUpInView {
	[super mouseUpInView];
	if(self.highlighted) {
		/// we detect if the user has clicked the action button
		if(hoveredActionButton) {
			TraceView *view = self.view;
			NSPoint mouseUpPoint = [layer convertPoint:view.mouseUpPoint fromLayer:view.layer];
			if(NSPointInRect(mouseUpPoint, actionButtonLayer.frame)) {
				Mmarker *marker = (Mmarker*)self.region;
				if(self.editState != editStateNil) {		/// if true, the action button looks like a checkbox
					marker.editState = editStateNil;		/// in which case, clicking it exits the edit state of the marker (and all its labels)
				} else {
					if(self.attachedPopover) {
						[self.attachedPopover close];
					}
					[self.menu popUpMenuPositioningItem:nil atLocation:view.mouseUpPoint inView:view];
				}
			}
		}
	}
}

# pragma mark - geometry and tracking areas

- (void)reposition {
	TraceView *view = self.view;
	float hScale = view.hScale;
	if(!view || hScale <= 0 || self.hidden) {
		return;
	}
	
	NSRect superLayerBounds = layer.superlayer.bounds;
	float startSize = self.startSize;
	float endSize = self.endSize;
	float startX = [self.view xForSize:startSize];     /// to get our frame, we convert our position in base pairs to points (x coordinates)
	regionRect = NSMakeRect(startX, 0, (endSize - startSize) * hScale, NSMaxY(superLayerBounds));
	
	if(self.highlighted) {
		/// when highlighted, our frame (used by the tracking area) gets a bit wider so that the user can more easily click an edge to resize us
		self.frame = NSInsetRect(regionRect, -2, 0);
	} else {
		self.frame = regionRect;
	}
	
	/// the rectangle representing our marker is a 3-point high bar
	regionRect.size.height = 3;
	
	/// if the label is not in the view's bounds (with some 2-point margin) and wasn't previously, we don't need to update the layer. The label isn't visible
	NSRect intersection = NSIntersectionRect(regionRect, NSInsetRect(superLayerBounds, -2, 0));
	if(intersection.size.width <= 0.1 && !CGRectIntersectsRect(layer.frame, superLayerBounds)) {
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
	if(self.attachedPopover) {
		self.attachedPopover.positioningRect = self.frame;
	}
	
	if(!traceView.isMoving && self.enabled && !self.dragged) {
		[self updateTrackingArea];  
	}
}

-(void)layoutInternalLayers {
	/// We don't do that in -layoutSublayersOfLayer: because it would be difficult to know if sublayers should be positioned with animation.
	/// The -animated property of the label may not be appropriate when that method is called
	
	/// The name is at the middle of the part of the marker label that is visible
	NSRect visibleMarkerRect = NSIntersectionRect(regionRect, layer.superlayer.bounds);
	CGPoint position = CGPointMake(NSMidX(visibleMarkerRect) - regionRect.origin.x - NSMidX(stringLayer.bounds), 3);
	if(!actionButtonLayer.hidden) {
		position.x -= actionButtonLayer.bounds.size.width/2 - 0.5;
		if(position.x < 1) {
			position.x = 1;		/// makes sure the button is visible even if the label is very short
		}
	}
	/// we position the button even if hidden. Otherwise, it may arrive from a distance when we get hovered
	actionButtonLayer.position = position;

	stringLayer.position = actionButtonLayer.hidden? CGPointMake(position.x, 4) : CGPointMake(NSMaxX(actionButtonLayer.frame) + 1, 4);
	
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
	if (actionButtonArea) {
		[view removeTrackingArea:actionButtonArea];
		[view removeToolTip:toolTipTag];
		actionButtonArea = nil;
	}
	if(!actionButtonLayer.hidden) {
		NSRect buttonFrame = [actionButtonLayer convertRect:actionButtonLayer.bounds toLayer:view.layer];
		actionButtonArea = [self addTrackingAreaForRect:buttonFrame];
		BOOL hovered = hoveredActionButton;
		hoveredActionButton = (NSPointInRect(view.mouseLocation, buttonFrame));
		if(hoveredActionButton != hovered) {
			[self updateActionButton];
		}
		
		toolTipTag = [view addToolTipRect:buttonFrame owner:self userData:nil];
	}
}



-(void)setFrame:(NSRect)frame {
	_frame = frame;
}


# pragma mark - menu and actions

- (NSString *)description {
	/// This describes what the action button does
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
		[_menu addItemWithTitle:@"Adjust Offset" action:@selector(setEditStateFromMenuItem:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:@"marker offset"]];
		[_menu.itemArray.lastObject setTag:editStateOffset];
		[_menu addItemWithTitle:@"Copy Offset" action:@selector(copyOffset:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:@"copy"]];
		[_menu addItemWithTitle:@"Paste Offset" action:@selector(pasteOffset:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:@"paste offset"]];
		[_menu addItemWithTitle:@"Remove Offset" action:@selector(removeOffset:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:@"close"]];
	
		for(NSMenuItem *item in self.menu.itemArray) {
			if(!item.submenu) {
				item.target = self;
			}
		}
	}
	return _menu;
}


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if(menuItem.action == @selector(copyOffset:) || menuItem.action == @selector(removeOffset:)) {
		/// We only copy or reset an offset that is not equal to `MarkerOffsetNone`.
		Chromatogram *sample = traceView.trace.chromatogram;
		for(Genotype *genotype in sample.genotypes) {
			if(genotype.marker == self.region) {
				MarkerOffset offset = genotype.offset;
				if(offset.intercept != 0.0 && offset.intercept != 1.0) {
					menuItem.hidden = NO;
					return YES;
				}
			}
		}
		menuItem.hidden = YES;
		return NO;
	}
	
	if(menuItem.action == @selector(pasteOffset:)) {
		NSDictionary *dic = Chromatogram.markerOffsetDictionaryFromGeneralPasteBoard;
		if(dic && traceView.trace) {
			NSString *URI = self.region.objectID.URIRepresentation.absoluteString;
			NSData *offsetData = dic[URI];
			if([offsetData isKindOfClass:NSData.class] && offsetData.length == sizeof(MarkerOffset)) {
				menuItem.hidden = NO;
				menuItem.representedObject = offsetData;
				return YES;
			}
		}
		menuItem.representedObject = nil;
		menuItem.hidden = YES;
		return NO;
	}
	
	BOOL valid = YES;
	NSInteger tag = menuItem.tag;
	if(tag != editStateNil && self.editState != editStateNil) {
		/// if we are already in an edit state, we disable any item that sets an edit state
		valid = NO;
	} else if (tag == editStateBinSet) {
		/// if the target is the bin set, we check if the marker indeed has bins
		Mmarker *marker = self.region;
		valid = marker.bins.count > 0;		/// if there is no bin set, we disable the menu that allows to move it
	} else if(tag == editStateOffset || menuItem.action == @selector(removeOffset:)) {
		Mmarker *marker = self.region;
		valid = marker.bins.count > 0 && self.view.trace;		/// if there is no bin set, we disable the menu that allows to move it
	}
	menuItem.hidden = !valid;
	return valid;
	
}



- (void)zoom:(id)sender {
	[traceView zoomToMarkerLabel:self];
}


-(void)removeOffset:(NSMenuItem *)sender {
	[self _updateOffset:MarkerOffsetNone];
}


-(void)copyOffset:(id) sender {
	Chromatogram *sample = traceView.trace.chromatogram;
	for(Genotype *genotype in sample.genotypes) {
		if(genotype.marker == self.region) {
			NSPasteboard *pasteBoard = NSPasteboard.generalPasteboard;
			[pasteBoard clearContents];
			[pasteBoard writeObjects:@[genotype]];
			return;
		}
	}
}


-(void)pasteOffset:(NSMenuItem *) sender {
	NSData *offsetData = sender.representedObject;
	if(offsetData) {
		MarkerOffset offset = MarkerOffsetNone;
		[offsetData getBytes:&offset length:sizeof(MarkerOffset)];
		[self _updateOffset:offset];
		[self.view.undoManager setActionName:@"Paste Marker Offset"];
	}
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
		/// the edit state is only reflected in the icon shown by the action button.
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
			newMarkerPopover.markerStartTextField.delegate = self;
			newMarkerPopover.markerEndTextField.delegate = self;
			newMarkerPopover.delegate = self;
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
	if([RegionLabel instancesRespondToSelector:@selector(popoverShouldClose:)]) {
		return [super popoverShouldClose:popover];
	}
	return YES;
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
	marker.motiveLength = newMarkerPopover.motiveLength;
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



/// The tag used to identify the controls in the addBinsPopover
/// these tags are defined in IB
enum addBinPopoverTag : NSInteger {
	binStartTextFieldTag = 4,
	binEndTextFieldTag = 5,
	addBinSetCancelButtonTag = 6,
	addBinsButtonTag = 7,
	binWidthSliderTag = 8,
	binSpacingButtonTag = 9,
	existingBinsCheckboxTag = 10
} addBinPopoverTag;



-(void)spawnAddBinsPopover:(NSMenuItem *)sender {
	if(!addBinsPopover) {
		addBinsPopover = NSPopover.new;
		NSViewController *controller = [[NSViewController alloc] initWithNibName:@"AutoBinPopover" bundle:nil];
		addBinsPopover.contentViewController = controller;
		addBinsPopover.behavior = NSPopoverBehaviorSemitransient;
		NSButton *cancelButton = [controller.view viewWithTag:addBinSetCancelButtonTag];
		cancelButton.action = @selector(close);
		cancelButton.target = addBinsPopover;
	}
	
	NSView *view = addBinsPopover.contentViewController.view;
	addBinsPopover.delegate = self;
	Mmarker *marker = self.region;
	NSTextField *startBinTextField = [view viewWithTag:binStartTextFieldTag];
	startBinTextField.intValue = round(marker.start + 0.5) +1;
	startBinTextField.delegate = self;
	NSTextField *endBinTextfield = [view viewWithTag:binEndTextFieldTag];
	endBinTextfield.intValue = (int)marker.end -1;
	endBinTextfield.delegate = self;
	NSButton *addBinsButton = [view viewWithTag:addBinsButtonTag];
	addBinsButton.target = self;
	addBinsButton.action = @selector(addBinSet:);
	NSPopUpButton *binSpacingButton = [view viewWithTag:binSpacingButtonTag];
	[binSpacingButton selectItemAtIndex:marker.motiveLength-1];
	
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
	} else if([RegionLabel instancesRespondToSelector:@selector(controlTextDidEndEditing:)]) {
		[super controlTextDidEndEditing:obj];
	}
}


/// Adds a set of bins to our marker based on specifications defined by the user on the popover (to which the sender belongs)
-(void)addBinSet:(NSButton *)sender {
	NSView *view = addBinsPopover.contentViewController.view;
	NSTextField *startBinTextField = [view viewWithTag:binStartTextFieldTag];
	NSTextField *endBinTextfield = [view viewWithTag:binEndTextFieldTag];
	NSSlider *binWidthSlider = [view viewWithTag:binWidthSliderTag];
	NSPopUpButton *binSpacingPopup = [view viewWithTag:binSpacingButtonTag];
	NSButton *removeAllBinsButton = [view viewWithTag:existingBinsCheckboxTag];
	
	Mmarker *marker = self.region;
	if(!marker || !startBinTextField || !endBinTextfield || !binWidthSlider || !binSpacingPopup) {
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
	
	NSInteger binSpacing = binSpacingPopup.indexOfSelectedItem + 1;
	if(binSpacing < 1) {
		binSpacing = 1;
	}
	
	if(binWidth >= binSpacing) {
		binWidth = binSpacing - 0.1;
	}
	
	
	float markerStart = marker.start + 0.1;
	float markerEnd = marker.end - 0.1;
	NSMutableSet *bins = NSMutableSet.new;
	NSMutableSet *binsToRemove = NSMutableSet.new;
	BOOL removeAllBins = removeAllBinsButton.state == NSControlStateValueOn;
	
	for(float i = binSetStart; i <= binSetEnd; i+= binSpacing) {
		float binStart = i - binWidth/2;
		float binEnd = i + binWidth/2;
		if(binStart >= markerStart && binEnd < markerEnd) {
			if(!removeAllBins) {
				for(Bin *bin in marker.bins) {
					if(bin.start < binEnd+0.1 && bin.end > binStart-0.1) {
						[binsToRemove addObject:bin];
					}
				}
			}
			Bin *newBin = [[Bin alloc] initWithContext:self.region.managedObjectContext];
			newBin.start = binStart;
			newBin.end = binEnd;
			[newBin autoName];
			[bins addObject:newBin];
		}
	}
	
	if(bins.count > 0 || binsToRemove.count > 0 || (removeAllBins && marker.bins.count > 0)) {
		[addBinsPopover close];
		NSUndoManager *undoManager = self.view.undoManager;
		[undoManager setActionName:@"Generate Bins"];
		if(removeAllBins) {
			marker.bins = bins;
		} else {
			[marker removeBins:binsToRemove];
			[marker addBins: bins];
		}
		
		/// we allow the user to move the new bin set (which also forces to show bins regardless of the showBins property of the view)
		marker.editState = editStateBinSet;
		
		/// if the user undoes the addition of bins, it makes sense to exit the edit state.
		[undoManager registerUndoWithTarget:self selector:@selector(exitBinSetEditState) object:nil];

	} 
	
	if(bins.count == 0) {
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
	if(!NSPointInRect(mouseUpPoint, actionButtonLayer.frame)) {
		/// we don't show the popover if the double click happened on the action button
		[self spawnRegionPopover:sender];
	}
}





@end
