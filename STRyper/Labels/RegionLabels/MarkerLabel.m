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

@interface MarkerLabel ()

/// properties bound to UI elements in the `addBinsPopover`.
@property (nonatomic) float binSetStart;
@property (nonatomic) float binSetEnd;
@property (nonatomic) NSInteger binSpacing;
@property (nonatomic) float binWidth;

@end


@implementation MarkerLabel {
	/// As these labels are not drawn in the trace view (their "view" property is the marker view), it is useful to keep a reference to the traceView
	__weak TraceView *traceView;
	
	ChannelNumber channel;
	NSColor *disabledColor, *hoveredColor, *defaultColor;
	
	/// Images used for the action button. We use CGImageRef that we update given the application appearance.
	CGImageRef actionRoundImageRef, actionRoundHoveredImageRef, actionCheckImageRef, actionCheckHoveredImageRef;
	
	CALayer *actionButtonLayer;	/// the layer symbolizing the button that can be clicked to popup the menu (or end editing)
								/// It is more convenient than using an NSButton because we make it a sublayer of our layer
	__weak NSTrackingArea *actionButtonArea; /// A tracking area to determine if the action button is hovered
	NSToolTipTag toolTipTag;		/// a tag for a tooltip indicating the action button role
	BOOL actionButtonIsHovered;		/// Whether the action button is hovered
	
}


# pragma mark - attributes and appearance

static NSImage *actionRoundImage, *actionRoundHoveredImage, *actionCheckImage, *actionCheckHoveredImage;

+ (void)initialize {
	if (self == [MarkerLabel class]) {
		if(!actionRoundImage) {
			actionCheckHoveredImage = [NSImage imageNamed:ACImageNameActionCheckHovered];
			actionRoundHoveredImage = [NSImage imageNamed:ACImageNameActionRoundHovered];
			actionCheckImage = [NSImage imageNamed:ACImageNameActionCheck];
			actionRoundImage = [NSImage imageNamed:ACImageNameActionRound];
		}
	}
}


- (BOOL)isMarkerLabel {
	return YES;
}


- (instancetype)init
{
	self = [super init];
	if (self) {
		channel = -1;
		layer.masksToBounds = YES;			/// the marker's name is clipped by the layer to avoid overlapping between marker names
		layer.borderColor = NSColor.grayColor.CGColor;
		layer.bounds = CGRectMake(0, -3, 50, 20);
		/// we use -3 because we place the layer bottom edge 3 points below the view, so as to hide the bottom edge of the border when it is highlighted.
		
		stringLayer.fontSize = 10.0;
		stringLayer.allowsFontSubpixelQuantization = YES;
		stringLayer.anchorPoint = CGPointMake(0,0);
		[layer addSublayer:stringLayer];
		
		[layer addSublayer:bandLayer];
		actionButtonLayer = CALayer.new;
		actionButtonLayer.hidden = YES;
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
		self.needsUpdateAppearance = YES;
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
	BOOL highlighted = self.highlighted;
	BOOL hovered = self.hovered;
	BOOL enabled = self.enabled;
	if(hovered || highlighted) {
		bandLayer.backgroundColor = hoveredColor.CGColor;
	} else {
		bandLayer.backgroundColor = enabled ? defaultColor.CGColor : disabledColor.CGColor;
	}
	
	if(actionButtonLayer) {
		EditState editState = self.editState;
		BOOL wasHidden = actionButtonLayer.hidden;
		BOOL hidden = (editState == editStateNil && !hovered && !highlighted) || !enabled || !self.region;
		actionButtonLayer.hidden = hidden;
		[self setActionButtonContent];
		
		if(wasHidden != hidden) {
			/// we reposition the label internal layers as the button layer's change in visibility changes the name's position
			[self layoutInternalLayers];
			[self updateButtonArea];
		}
	}
	[super updateAppearance];
}


- (void)updateForTheme {
	[super updateForTheme];
	defaultColor = self.view.colorsForChannels[channel];
	/// We use a horizontal segment to represent the marker range. The color is based on the channel, but a bit brighter
	/// The color is brighter when the label is hovered
	hoveredColor = [defaultColor blendedColorWithFraction:0.4 ofColor:NSColor.whiteColor];
	if(_hovered || _highlighted) {
		bandLayer.backgroundColor = hoveredColor.CGColor;
	} else {
		bandLayer.backgroundColor = _enabled ? defaultColor.CGColor : disabledColor.CGColor;
	}
	/// We update the images of the action button (template images that are brighter in dark mode)
	CGImageRelease(actionRoundImageRef);
	actionRoundImageRef = CGImageRetain([actionRoundImage CGImageForProposedRect:nil context:nil hints:nil]);
	CGImageRelease(actionRoundHoveredImageRef);
	actionRoundHoveredImageRef = CGImageRetain([actionRoundHoveredImage CGImageForProposedRect:nil context:nil hints:nil]);
	CGImageRelease(actionCheckImageRef);
	actionCheckImageRef = CGImageRetain([actionCheckImage CGImageForProposedRect:nil context:nil hints:nil]);
	CGImageRelease(actionCheckHoveredImageRef);
	actionCheckHoveredImageRef = CGImageRetain([actionCheckHoveredImage CGImageForProposedRect:nil context:nil hints:nil]);
	
	[self setActionButtonContent];
}


-(void)setActionButtonContent {
	if(actionButtonLayer) {
		CGImageRef buttonImage;
		BOOL inEdit = self.editState != editStateNil;
		if(actionButtonIsHovered) {
			buttonImage = inEdit? actionCheckHoveredImageRef : actionRoundHoveredImageRef;
		} else {
			buttonImage = inEdit? actionCheckImageRef : actionRoundImageRef;
		}
		if(buttonImage) {
			actionButtonLayer.contents = (__bridge id _Nullable)buttonImage;
		}
	}
}

# pragma mark - user events

- (void)mouseEntered:(NSEvent *)theEvent {
	if(theEvent.trackingArea == actionButtonArea) {
		actionButtonIsHovered = YES;
		self.needsUpdateAppearance = YES;
	} else {
		[super mouseEntered:theEvent];
	}
}


- (void)mouseExited:(NSEvent *)theEvent {
	if(theEvent.trackingArea == actionButtonArea) {
		actionButtonIsHovered = NO;
		self.needsUpdateAppearance = YES;
	} else {
		[super mouseExited:theEvent];
	}
}


- (void)mouseUpInView {
	[super mouseUpInView];
	if(self.highlighted) {
		/// we detect if the user has clicked the action button
		if(actionButtonIsHovered) {
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

- (void)mouseDraggedInView {
	/// Overridden, as this label can only be dragged (resized) by dragging its edges (not between edges)
	if(self.clickedEdge == leftEdge || self.clickedEdge == rightEdge) {
		[self drag];
	}
}

# pragma mark - geometry and tracking areas

- (void)reposition {
	TraceView *view = self.view;
	float hScale = view.hScale;
	if(!view || hScale <= 0) {
		return;
	}
	
	NSRect superLayerBounds = layer.superlayer.bounds;
	float startSize = self.startSize;
	float endSize = self.endSize;
	float startX = [self.view xForSize:startSize];     /// to get our frame, we convert our position in base pairs to points (x coordinates)
	regionRect = NSMakeRect(startX, 0, (endSize - startSize) * hScale, NSMaxY(superLayerBounds));
	self.frame = regionRect;
	
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
	/// the rectangle symbolizing the marker starts a big below the view to hide the bottom edge
	layer.frame = CGRectMake(regionRect.origin.x, -3, regionRect.size.width, regionRect.size.height + 3);
	bandLayer.frame = CGRectMake(0, 0, regionRect.size.width, 3); /// The band layer is a 3-point-thick bar.
	
	[self layoutInternalLayers];
	
	/// if we show a popover, we move it in sync with the label (the markerView doesn't scroll).
	if(self.attachedPopover) {
		self.attachedPopover.positioningRect = self.frame;
	}
}


-(void)layoutInternalLayers {
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
		BOOL hovered = actionButtonIsHovered;
		actionButtonIsHovered = (NSPointInRect(view.mouseLocation, buttonFrame));
		if(actionButtonIsHovered != hovered) {
			[self setActionButtonContent];
		}
		
		toolTipTag = [view addToolTipRect:buttonFrame owner:self userData:nil];
	}
}



-(void)setFrame:(NSRect)frame {
	_frame = frame;
}


# pragma mark - menu and actions


- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data {
	if(tag == toolTipTag) {
		if(self.editState == editStateNil) {
			return @"Show options";
		} else {
			return @"End editing";
		}
	}
	return @"";
}


- (NSMenu *)menu {
	_menu = super.menu;
	if(_menu.itemArray.count < 4) {
		[_menu addItemWithTitle:@"Zoom to Marker" action:@selector(zoom:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:ACImageNameLoupeBadge]];
		[_menu addItem:NSMenuItem.separatorItem];
		[_menu addItemWithTitle:@"Generate Bins" action:@selector(spawnAddBinsPopover:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:ACImageNameBinset]];
		[_menu addItemWithTitle:@"Edit Bins" action:@selector(setEditStateFromMenuItem:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:ACImageNameEditBins]];
		[_menu.itemArray.lastObject setTag:editStateBins];
		[_menu addItemWithTitle:@"Move all Bins" action:@selector(setEditStateFromMenuItem:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:ACImageNameMoveBins]];
		[_menu.itemArray.lastObject setTag:editStateBinSet];
		[_menu addItem:NSMenuItem.separatorItem];
		[_menu addItemWithTitle:@"Adjust Offset" action:@selector(setEditStateFromMenuItem:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:ACImageNameMarkerOffset]];
		[_menu.itemArray.lastObject setTag:editStateOffset];
		[_menu addItemWithTitle:@"Copy Offset" action:@selector(copyOffset:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:ACImageNameCopy]];
		[_menu addItemWithTitle:@"Paste Offset" action:@selector(pasteOffset:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:ACImageNamePasteOffset]];
		[_menu addItemWithTitle:@"Remove Offset" action:@selector(removeOffset:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:ACImageNameClose]];
		
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
		self.needsUpdateAppearance = YES;
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
	[(MarkerView *)self.view setNeedsUpdateContent:YES];
	
}



-(void)addMarker:(NSButton *) sender {
	[sender.window makeFirstResponder:nil];	/// this forces the fields of the popover to validate
	Mmarker *marker = self.region;
	[marker managedObjectOriginal_setPloidy: newMarkerPopover.diploid + 1];
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
	existingBinsCheckboxTag = 10,
	binWidthTextFieldTag = 11
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
	if(addBinsPopover.delegate != self) {
		NSView *view = addBinsPopover.contentViewController.view;
		Mmarker *marker = self.region;
		NSTextField *startBinTextField = [view viewWithTag:binStartTextFieldTag];
		NSTextField *endBinTextField = [view viewWithTag:binEndTextFieldTag];
		NSSlider *binWidthSlider = [view viewWithTag:binWidthSliderTag];
		NSTextField *binWidthTextField = [view viewWithTag:binWidthTextFieldTag];
		NSPopUpButton *binSpacingButton = [view viewWithTag:binSpacingButtonTag];
		NSButton *removeAllBinsButton = [view viewWithTag:existingBinsCheckboxTag];
		
		if(_binSetStart <= 0) {
			self.binSetStart = ceilf(marker.start) +1;
		}
		if(_binSetEnd <= 0) {
			self.binSetEnd = floorf(marker.end -1);
		}
		if(_binSpacing < 1 || _binSpacing > 7) {
			self.binSpacing = marker.motiveLength-1;
		}
		if(_binWidth < 0.5 || _binWidth > 1.5) {
			self.binWidth = 1.0;
		}
		
		NSDictionary *option = @{NSValidatesImmediatelyBindingOption:@YES};
		[startBinTextField bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(binSetStart)) options:option];
		[endBinTextField bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(binSetEnd)) options:option];
		[binSpacingButton bind:NSSelectedIndexBinding toObject:self withKeyPath:NSStringFromSelector(@selector(binSpacing)) options:option];
		[binWidthSlider bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(binWidth)) options:option];
		[binWidthTextField bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(binWidth)) options:nil];
		[removeAllBinsButton bind:NSEnabledBinding toObject:marker withKeyPath:@"bins.@count" options:nil];

		NSButton *addBinsButton = [view viewWithTag:addBinsButtonTag];
		addBinsButton.target = self;
		addBinsButton.action = @selector(addBinSet:);
		
		addBinsPopover.delegate = self;
	}
	
	[addBinsPopover showRelativeToRect:self.frame ofView:self.view preferredEdge:NSMaxYEdge];
	
}

- (void)popoverDidShow:(NSNotification *)notification {
	NSPopover *popover = notification.object;
	if(popover == addBinsPopover) {
		/// if the popover is spawn via a message sent by the contextual menu, it's text field isn't selected, so we force it.
		NSTextField *nameTextField = [popover.contentViewController.view viewWithTag:binStartTextFieldTag];
		[nameTextField selectText:self];
	} else {
		[super popoverDidShow:notification];
	}
}


-(BOOL)validateBinSetStart:(id *)ioValue error:(NSError **)error {
	NSNumber *start = *ioValue;
	if(start == nil) {
		*ioValue = @(_binSetStart);
		return YES;
	}
	float halfBinWidth = self.binWidth/2;
	
	float startValue = start.floatValue;
	float min = self.region.start + halfBinWidth + 0.1;
	float max = self.region.end - halfBinWidth - 0.1;
	
	if(startValue < min) {
		startValue = min;
	} else if(startValue > max) {
		startValue = max;
	}
	if(startValue > _binSetEnd) {
		self.binSetEnd = startValue;
	}
	*ioValue = @(startValue);
	return YES;
}



-(BOOL)validateBinSetEnd:(id *)ioValue error:(NSError **)error {
	NSNumber *end = *ioValue;
	if(end == nil) {
		*ioValue = @(_binSetStart);
		return YES;
	}
	float halfBinWidth = self.binWidth/2;
	
	float endValue = end.floatValue;
	float max = self.region.end - halfBinWidth - 0.1;
	float min = self.region.start + halfBinWidth + 0.1;
	
	if(endValue < min) {
		endValue = min;
	} else if(endValue > max) {
		endValue = max;
	}
	if(endValue < _binSetStart) {
		self.binSetStart = endValue;
	}
	*ioValue = @(endValue);
	return YES;
}


-(BOOL)validateBinWidth:(id *)ioValue error:(NSError **)error {
	NSNumber *width = *ioValue;
	float widthValue = width.floatValue;
	if(widthValue < 0.1) {
		widthValue = 0.1;
	} else if(widthValue > 2) {
		widthValue = 2;
	}
	if(widthValue > _binSpacing + 0.9) {
		widthValue = _binSpacing + 0.9;
	}
	*ioValue = @(widthValue);
	return YES;
}


- (void)setBinSpacing:(NSInteger)binSpacing {
	_binSpacing = binSpacing;
	if(_binWidth > binSpacing + 0.9) {
		self.binWidth = binSpacing + 0.9;
	}
}


/// Adds a set of bins to our marker based on specifications defined by the user on the popover (to which the sender belongs)
-(void)addBinSet:(NSButton *)sender {
	NSView *view = addBinsPopover.contentViewController.view;
	NSButton *removeAllBinsButton = [view viewWithTag:existingBinsCheckboxTag];
	
	Mmarker *marker = self.region;

	NSString *correction;
	
	float markerStart = marker.start + 0.1;
	float markerEnd = marker.end - 0.1;
	NSMutableSet *bins = NSMutableSet.new;
	NSMutableSet *binsToRemove = NSMutableSet.new;
	BOOL removeAllBins = removeAllBinsButton.state == NSControlStateValueOn;
	
	int skippedBins = 0;
	float binSetStart = self.binSetStart;
	float binSetEnd = self.binSetEnd;
	NSInteger binSpacing = self.binSpacing + 1;
	float binWidth = self.binWidth;
	if(binSpacing < 1) {
		binSpacing = 1;
	}
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
			if(newBin) {
				newBin.start = binStart;
				newBin.end = binEnd;
				[newBin autoName];
				[bins addObject:newBin];
			}
		} else {
			skippedBins++;
		}
	}
	
	if(skippedBins && !correction) {
		correction = skippedBins > 1? [NSString stringWithFormat:@"%d bins out of the marker range were not added.", skippedBins]:
		 @"1 bin out of the marker range was not added.";
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
		
	} 
	
	if(correction) {
		NSError *error = [NSError errorWithDescription:correction suggestion:@""];
		[[NSAlert alertWithError:error] beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
		}];
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


- (void)dealloc {
	CGImageRelease(actionCheckImageRef);
	actionCheckImageRef = NULL;
	CGImageRelease(actionCheckHoveredImageRef);
	actionCheckHoveredImageRef = NULL;
	CGImageRelease(actionRoundImageRef);
	actionRoundImageRef = NULL;
	CGImageRelease(actionRoundHoveredImageRef);
	actionRoundHoveredImageRef = NULL;
}




@end
