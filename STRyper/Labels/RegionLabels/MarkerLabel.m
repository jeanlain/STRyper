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
	
	/// Images used for the chevron/checkbox. We use CGImageRef that we update given the application appearance.
	CGImageRef actionRoundImageRef, actionRoundHoveredImageRef, actionCheckImageRef, actionCheckHoveredImageRef;
	
	CALayer *chevronCheckBoxLayer;	/// the layer for the chevron/checkbox showing next to the marker name.
									/// It is more convenient than using an NSButton because we make it a sublayer of our layer
	__weak NSTrackingArea *nameArea; /// A tracking area to determine if the marker label name is hovered (to change the chevron's appearance).
	BOOL labelNameIsHovered;		/// Whether the label name is hovered
	BOOL needsUpdateStringLayerWidth;
}


# pragma mark - attributes and appearance

static NSImage *chevronImage, *chevronHoveredImage, *actionCheckImage, *actionCheckHoveredImage;

+ (void)initialize {
	if (self == MarkerLabel.class) {
		if(!chevronImage) {
			actionCheckHoveredImage = [NSImage imageNamed:ACImageNameActionCheckHovered];
			chevronHoveredImage = [NSImage imageNamed:ACImageNameActionRoundHovered];
			actionCheckImage = [NSImage imageNamed:ACImageNameActionCheck];
			chevronImage = [NSImage imageNamed:ACImageNameActionRound];
		}
	}
}


- (BOOL)isMarkerLabel {
	return YES;
}


static CGFloat const buttonWidth = 15.0;
- (instancetype)init
{
	self = [super init];
	if (self) {
		channel = -1;
		layer.borderColor = NSColor.grayColor.CGColor;
		layer.bounds = CGRectMake(0.0, -3.0, 50.0, 20.0);
		/// we use -3 because we place the layer bottom edge 3 points below the view, so as to hide the bottom edge of the border when it is highlighted.
		
		stringLayer.fontSize = 10.0;
		stringLayer.anchorPoint = CGPointMake(0.5, 0.0);
		
		chevronCheckBoxLayer = CALayer.new;
		chevronCheckBoxLayer.hidden = YES;
		chevronCheckBoxLayer.delegate = self;
		chevronCheckBoxLayer.anchorPoint = CGPointMake(1, 0.0);
		chevronCheckBoxLayer.bounds = CGRectMake(0.0, 0.0, buttonWidth, buttonWidth);
		[stringLayer addSublayer:chevronCheckBoxLayer];
		
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
		/// The bandLayer is not a sublayer of the layer, to avoid appearing behind the layer's border.
		[view.backgroundLayer addSublayer:bandLayer];
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
	
	if(chevronCheckBoxLayer) {
		EditState editState = self.editState;
		BOOL wasHidden = chevronCheckBoxLayer.hidden;
		BOOL hidden = (editState == editStateNil && !hovered && !highlighted) || !enabled || !self.region;
		chevronCheckBoxLayer.hidden = hidden;
		[self setActionButtonContent];
		
		if(wasHidden != hidden) {
			/// we reposition the label internal layers as the button layer's change in visibility changes the name's position
			needsUpdateStringLayerWidth = YES;
			[self layoutInternalLayers];
			[self updateButtonArea];
		}
	}
	[super updateAppearance];
}

- (void)setHovered:(BOOL)hovered {
	super.hovered = hovered;
	bandLayer.zPosition = hovered? 1:0; /// Makes sure the marker names is not masked by the name of another marker nearby.
}

- (void)updateColors {
	stringLayer.foregroundColor = NSColor.textColor.CGColor;
	stringLayer.backgroundColor = self.view.backgroundColor.CGColor;
	defaultColor = self.view.colorsForChannels[channel];
	/// We use a horizontal segment to represent the marker range. The color is based on the channel, but a bit brighter
	/// The color is brighter when the label is hovered
	hoveredColor = [defaultColor blendedColorWithFraction:0.4 ofColor:NSColor.whiteColor];
	layer.borderColor = hoveredColor.CGColor;
	if(_hovered || _highlighted) {
		bandLayer.backgroundColor = hoveredColor.CGColor;
	} else {
		bandLayer.backgroundColor = _enabled ? defaultColor.CGColor : disabledColor.CGColor;
	}
	/// We update the images of the chevron button (template images that are brighter in dark mode)
	CGImageRelease(actionRoundImageRef);
	actionRoundImageRef = CGImageRetain([chevronImage CGImageForProposedRect:nil context:nil hints:nil]);
	CGImageRelease(actionRoundHoveredImageRef);
	actionRoundHoveredImageRef = CGImageRetain([chevronHoveredImage CGImageForProposedRect:nil context:nil hints:nil]);
	CGImageRelease(actionCheckImageRef);
	actionCheckImageRef = CGImageRetain([actionCheckImage CGImageForProposedRect:nil context:nil hints:nil]);
	CGImageRelease(actionCheckHoveredImageRef);
	actionCheckHoveredImageRef = CGImageRetain([actionCheckHoveredImage CGImageForProposedRect:nil context:nil hints:nil]);
	
	[self setActionButtonContent];
}


-(void)setActionButtonContent {
	if(chevronCheckBoxLayer) {
		CGImageRef buttonImage;
		BOOL inEdit = self.editState != editStateNil;
		if(labelNameIsHovered) {
			buttonImage = inEdit? actionCheckHoveredImageRef : actionRoundHoveredImageRef;
		} else {
			buttonImage = inEdit? actionCheckImageRef : actionRoundImageRef;
		}
		if(buttonImage) {
			chevronCheckBoxLayer.contents = (__bridge id _Nullable)buttonImage;
		}
	}
}

# pragma mark - user events

- (void)mouseEntered:(NSEvent *)theEvent {
	if(theEvent.trackingArea == nameArea) {
		labelNameIsHovered = YES;
		self.needsUpdateAppearance = YES;
	} else {
		[super mouseEntered:theEvent];
	}
}


- (void)mouseExited:(NSEvent *)theEvent {
	if(theEvent.trackingArea == nameArea) {
		labelNameIsHovered = NO;
		self.needsUpdateAppearance = YES;
	} else {
		[super mouseExited:theEvent];
	}
}


- (void)mouseUpInView {
	[super mouseUpInView];
	if(self.highlighted) {
		/// we detect if the user has clicked the label name
		if(labelNameIsHovered) {
			TraceView *view = self.view;
			NSPoint mouseUpPoint = [layer convertPoint:view.mouseUpPoint fromLayer:view.layer];
			if(NSPointInRect(mouseUpPoint, stringLayer.frame)) {
				if(self.editState != editStateNil) {		/// if true, the chevron is replaced with a checkbox
					self.editState = editStateNil;			/// in which case, clicking it exits the edit state
				} else {
					if(self.attachedPopover) {
						[self.attachedPopover close];
					}
					CGPoint buttonOrigin = nameArea.rect.origin;
					buttonOrigin.y -= chevronCheckBoxLayer.bounds.size.height * 0.5 - 1.0;
					[self.menu popUpMenuPositioningItem:nil atLocation:buttonOrigin inView:view];
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
	if(!view || hScale <= 0.0f) {
		return;
	}
	
	NSRect superLayerBounds = layer.superlayer.bounds;
	float startSize = self.startSize;
	float endSize = self.endSize;
	CGFloat startX = [self.view xForSize:startSize];     /// to get our frame, we convert our position in base pairs to points (x coordinates)
	regionRect = NSMakeRect(startX, 0.0, (endSize - startSize) * hScale, NSMaxY(superLayerBounds));
	self.frame = regionRect;
	
	NSRect intersection = NSIntersectionRect(regionRect, NSInsetRect(superLayerBounds, -2.0, 0.0));

	/// to avoid drawing a layer that is very large (at very high hScale), we won't draw what is not visible
	regionRect = intersection;
	
	/// the rectangle symbolizing the marker starts a bit below the view to hide the bottom edge
	layer.frame = CGRectMake(regionRect.origin.x, -3.0, regionRect.size.width, regionRect.size.height + 3.0);
	bandLayer.frame = CGRectMake(regionRect.origin.x, 0.0, regionRect.size.width, 3.0); /// The band layer is a 3-point-thick bar.
		
	if(intersection.size.width > 0) {
		[self layoutInternalLayers];
	}
	
	/// if we show a popover, we move it in sync with the label (the markerView doesn't scroll).
	if(self.attachedPopover) {
		self.attachedPopover.positioningRect = regionRect;
	}
}


-(void)layoutInternalLayers {
	NSRect visibleMarkerRect = NSIntersectionRect(regionRect, bandLayer.superlayer.bounds);
	CGFloat visibleWidth = visibleMarkerRect.size.width;
	if(needsUpdateStringLayerWidth) {
		CGSize preferredSize = stringLayer.preferredFrameSize;
		if(visibleWidth > 0.0 && !chevronCheckBoxLayer.hidden) {
			preferredSize.width += buttonWidth;
		}
		stringLayer.bounds = CGRectMake(0.0, 0.0, preferredSize.width, preferredSize.height);
	}
	chevronCheckBoxLayer.position = CGPointMake(stringLayer.bounds.size.width, -1.0);
	stringLayer.position = CGPointMake(visibleWidth/2, 4.0);
}


- (void)updateTrackingArea {
	[super updateTrackingArea];
	[self updateButtonArea];
}


-(void) updateButtonArea {
	TraceView *view = self.view;
	if (nameArea) {
		[view removeTrackingArea:nameArea];
		nameArea = nil;
	}
	if(!chevronCheckBoxLayer.hidden) {
		CGRect buttonFrame = [stringLayer convertRect:stringLayer.bounds toLayer:view.layer];
		nameArea = [self addTrackingAreaForRect:buttonFrame];
		BOOL hovered = labelNameIsHovered;
		labelNameIsHovered = (NSPointInRect(view.mouseLocation, buttonFrame));
		if(labelNameIsHovered != hovered) {
			[self setActionButtonContent];
		}
	}
}



-(void)setFrame:(NSRect)frame {
	_frame = frame;
}


# pragma mark - menu and actions


- (NSMenu *)menu {
	_menu = super.menu;
	if(_menu.itemArray.count < 4) {
		[_menu addItemWithTitle:@"Zoom to Marker" action:@selector(zoom:) keyEquivalent:@""];
		_menu.itemArray.lastObject.image = [NSImage imageNamed:ACImageNameZoomToMarker];
		[_menu addItem:NSMenuItem.separatorItem];
		[_menu addItemWithTitle:@"Generate Bins" action:@selector(spawnAddBinsPopover:) keyEquivalent:@""];
		_menu.itemArray.lastObject.image = [NSImage imageNamed:ACImageNameBinset];
		[_menu addItemWithTitle:@"Edit Bins" action:@selector(setEditStateFromMenuItem:) keyEquivalent:@""];
		_menu.itemArray.lastObject.image = [NSImage imageNamed:ACImageNameEditBins];
		[_menu.itemArray.lastObject setTag:editStateBins];
		[_menu addItemWithTitle:@"Move all Bins" action:@selector(setEditStateFromMenuItem:) keyEquivalent:@""];
		_menu.itemArray.lastObject.image = [NSImage imageNamed:ACImageNameMoveBins];
		[_menu.itemArray.lastObject setTag:editStateBinSet];
		[_menu addItem:NSMenuItem.separatorItem];
		[_menu addItemWithTitle:@"Adjust Offset" action:@selector(setEditStateFromMenuItem:) keyEquivalent:@""];
		_menu.itemArray.lastObject.image = [NSImage imageNamed:ACImageNameMarkerOffset];
		[_menu.itemArray.lastObject setTag:editStateOffset];
		[_menu addItemWithTitle:@"Copy Offset" action:@selector(copyOffset:) keyEquivalent:@""];
		_menu.itemArray.lastObject.image = [NSImage imageNamed:ACImageNameCopy];
		[_menu addItemWithTitle:@"Paste Offset" action:@selector(pasteOffset:) keyEquivalent:@""];
		_menu.itemArray.lastObject.image = [NSImage imageNamed:ACImageNamePasteOffset];
		[_menu addItemWithTitle:@"Remove Offset" action:@selector(removeOffset:) keyEquivalent:@""];
		_menu.itemArray.lastObject.image = [NSImage imageNamed:ACImageNameReset];
		
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
		if(sample) {
			for(Genotype *genotype in sample.genotypes) {
				if(genotype.marker == self.region) {
					MarkerOffset offset = genotype.offset;
					if(offset.intercept != 0.0 && offset.intercept != 1.0) {
						menuItem.hidden = NO;
						return YES;
					}
				}
			}
		} else if(traceView.loadedGenotypes.count > 0 && traceView.marker == self.region) {
			if(menuItem.action == @selector(removeOffset:)) {
				for(Genotype *genotype in traceView.loadedGenotypes) {
					MarkerOffset offset = genotype.offset;
					if(offset.intercept != 0.0f || offset.slope != 1.0f) {
						menuItem.hidden = NO;
						return YES;
					}
				}
			}
		}
		menuItem.hidden = YES;
		return NO;
	}
	
	if(menuItem.action == @selector(pasteOffset:)) {
		NSDictionary *dic = Chromatogram.markerOffsetDictionaryFromGeneralPasteBoard;
		if(dic && (traceView.trace || traceView.loadedGenotypes.count > 0)) {
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
		valid = marker.bins.count > 0 && (traceView.trace || traceView.loadedGenotypes.count > 0);		/// if there is no bin set, we disable the menu that allows to move it
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
	self.editState = sender.tag;
	if(self.editState != editStateNil && self.editState != editStateBins) {
		BaseRange range = self.range;
		BaseRange viewRange = self.view.visibleRange;
		float overlap = OverlapOfRanges(range, viewRange);
		if(overlap < range.len/2 && overlap < viewRange.len/2) {
			[self.view zoomToMarkerLabel:self];
		}
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
	
	Mmarker *marker = self.region;
	float markerStart =  ceilf(marker.start) +1.0f;
	float markerEnd = floorf(marker.end -1.0f);
	
	if(_binSetStart < markerStart || _binSetStart > markerEnd) {
		self.binSetStart = markerStart;
	}
	if(_binSetEnd < markerStart || _binSetEnd > markerEnd) {
		self.binSetEnd = markerEnd;
	}
	
	if(_binSetEnd < _binSetStart) {
		self.binSetStart = markerStart;
		self.binSetEnd = markerEnd;
	}
	
	if(_binSpacing != marker.motiveLength-1) {
		self.binSpacing = marker.motiveLength-1;
	}
	if(_binWidth < 0.5 || _binWidth > 1.5) {
		self.binWidth = 1.0;
	}
	
	if(addBinsPopover.delegate != self) {
		NSView *view = addBinsPopover.contentViewController.view;
		NSTextField *startBinTextField = [view viewWithTag:binStartTextFieldTag];
		NSTextField *endBinTextField = [view viewWithTag:binEndTextFieldTag];
		NSSlider *binWidthSlider = [view viewWithTag:binWidthSliderTag];
		NSTextField *binWidthTextField = [view viewWithTag:binWidthTextFieldTag];
		NSPopUpButton *binSpacingButton = [view viewWithTag:binSpacingButtonTag];
		NSButton *removeAllBinsButton = [view viewWithTag:existingBinsCheckboxTag];
		
		
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
	float min = self.region.start + halfBinWidth + 0.1f;
	float max = self.region.end - halfBinWidth - 0.1f;
	
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
	float max = self.region.end - halfBinWidth - 0.1f;
	float min = self.region.start + halfBinWidth + 0.1f;
	
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
	if(widthValue < 0.1f) {
		widthValue = 0.1f;
	} else if(widthValue > 2.0f) {
		widthValue = 2.0f;
	}
	if(widthValue > _binSpacing + 0.9f) {
		widthValue = _binSpacing + 0.9f;
	}
	*ioValue = @(widthValue);
	return YES;
}


- (void)setBinSpacing:(NSInteger)binSpacing {
	_binSpacing = binSpacing;
	if(_binWidth > binSpacing + 0.9f) {
		self.binWidth = binSpacing + 0.9f;
	}
}


/// Adds a set of bins to our marker based on specifications defined by the user on the popover (to which the sender belongs)
-(void)addBinSet:(NSButton *)sender {
	NSView *view = addBinsPopover.contentViewController.view;
	[view.window makeFirstResponder:nil]; /// forces the validation of controls in the popover, hence updates bounds properties
	NSButton *removeAllBinsButton = [view viewWithTag:existingBinsCheckboxTag];
	
	Mmarker *marker = self.region;

	NSString *correction;
	
	float markerStart = marker.start + 0.1f;
	float markerEnd = marker.end - 0.1f;
	NSMutableSet *bins = NSMutableSet.new;
	NSMutableSet *binsToRemove = NSMutableSet.new;
	BOOL removeAllBins = removeAllBinsButton.state == NSControlStateValueOn;
	
	int skippedBins = 0;
	float binSetStart = self.binSetStart;
	float binSetEnd = self.binSetEnd;
	NSInteger binSpacing = self.binSpacing + 1;
	float binWidth = self.binWidth;
	if(binSpacing < 1.0f) {
		binSpacing = 1.0f;
	}
	for(float i = binSetStart; i <= binSetEnd; i+= binSpacing) {
		float binStart = i - binWidth/2;
		float binEnd = i + binWidth/2;
		if(binStart >= markerStart && binEnd < markerEnd) {
			if(!removeAllBins) {
				for(Bin *bin in marker.bins) {
					if(bin.start < binEnd+0.1f && bin.end > binStart-0.1f) {
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
		self.editState = editStateBinSet;
		[self.view zoomToMarkerLabel:self];
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
	if(!NSPointInRect(mouseUpPoint, stringLayer.frame)) {
		/// we don't show the popover if the double click happened on the name
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
