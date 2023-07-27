//
//  RegionLabel.m
//  STRyper
//
//  Created by Jean Peccoud on 07/03/2022.
//  Copyright © 2022 Jean Peccoud. All rights reserved.
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


#import "RegionLabel.h"
#import "Mmarker.h"
#import "TraceView.h"
#import "Genotype.h"
#import "SampleFolder.h"
#import "FolderListController.h"
#import "MarkerLabel.h"
#import "BinLabel.h"
#import "TraceViewMarkerLabel.h"
#import "NewMarkerPopover.h"



@implementation RegionLabel

@synthesize hoveredEdge = _hoveredEdge;


#pragma mark - initialization and base attributes setting

static NSArray *observedKeys;

+ (void)initialize {
	observedKeys = @[@"start", @"end", @"name", @"editState"];
	
}

+ (nullable instancetype)regionLabelWithRegion:(Region *)region view:(__kindof LabelView *)view {
	RegionLabel *label;
	if([region isKindOfClass:Mmarker.class]) {
		if([view isKindOfClass:TraceView.class]) {
			label = [[TraceViewMarkerLabel alloc] init];
		} else {
			label = [[MarkerLabel alloc] init];
		}
	} else {
		label = [[BinLabel alloc] init];
	}
	if(label) {
		label.view = view;
		label.region = region;
	}
	return label;
}


- (BOOL)highlightedOnMouseUp {
	/// These labels are only highlighted on mouseUp, to avoid unwanted dragging (of bins, in particular).
	/// The user has to select them, release the mouse, and then drag edges or the whole bin
	return YES;
}


- (id)representedObject {
	return self.region;
}



-(void) removeFromView {
	NSView *view = self.view;
	if (view) {
		[attachedPopover close];
	}
	if(bandLayer.superlayer) {
		[bandLayer removeFromSuperlayer];		/// the band layer may not be in the same view as the "layer", so we remove it from its parent separately
	}

	[super removeFromView];
}


- (void)updateAppearance {
	if(!layer || !defaultColor) {
		return;
	}
	/// we determine which layer gets the color, which differs between markerLabels and binLabels
	CALayer *coloredLayer = self.isMarkerLabel? bandLayer : layer;
	
	if(!self.enabled && !self.hovered) {
		coloredLayer.backgroundColor = disabledColor.CGColor;
	}
	coloredLayer.backgroundColor = (self.hovered || self.highlighted)? hoveredColor.CGColor : defaultColor.CGColor;
	
	/// when highlighted, we make our border visible to signify that we can be resized
	layer.borderWidth = (self.highlighted)? 1.0 : 0.0;
}


- (void)updateForTheme {
	if(self.isBinLabel) {
		bandLayer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
	}
	stringLayer.foregroundColor = NSColor.textColor.CGColor;
}

# pragma mark - reacting to region and view changes, geometry updates


/// We observe some keys of our region to update when they change
static void * const regionPropertyChangedContext = (void*)&regionPropertyChangedContext;


- (void)setRegion:(__kindof Region *)region {
	/// by this setter, we observe changes in the properties of our region and set some attributes
	if(region == self.region) {
		return;
	}
	
	[self stopObserving];
	_region = region;
	if(!_region) {
		return;
	}
	
	for (NSString *key in observedKeys) {
		[_region addObserver:self forKeyPath:key options:NSKeyValueObservingOptionNew context:regionPropertyChangedContext];
	}
	
	if(!self.isBinLabel) {
		/// the edit state is not relevant to bin labels.
		self.editState = self.region.editState;
	} 
	[self setName];
	
	_start = self.region.start;
	_end = self.region.end;
	[self updateAppearance];
}


- (void)stopObserving {
	if(_region) {
		for (NSString *key in observedKeys) {
			[_region removeObserver:self forKeyPath:key];
		}
	}
}


- (void)setName {
	NSString *name = self.region.name;
	if(!name || !stringLayer) {
		return;
	}
	stringLayer.string = name;
	CGSize size = stringLayer.preferredFrameSize;
	stringLayer.bounds = CGRectMake(0, 0, size.width, size.height);
	
	[self repositionInternalLayers];		/// the change in name requires repositioning the string layer
}


-(void)repositionInternalLayers {
	/// overridden
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context == regionPropertyChangedContext) {
		Region *region = (Region *)object;
		if([region valueForKey:keyPath] == nil) {
			/// This may be true if the region is being deleted, in which case we do nothing.
			return;
		} else {
			if([keyPath isEqualToString:@"editState"]) {
				self.editState = region.editState;
			}
			else if([keyPath isEqualToString:@"name"]){
				[self setName];
			}
			else {
				/// we close any popover we show if it is not the one changing the attributes of the region.
				if(attachedPopover && attachedPopover != regionPopover) {
					[attachedPopover performClose:self];
				}
				/// If we show the region popover, we update the start and end values to reflect those of our region
				if(regionPopover.delegate == self) {
					for (NSTextField *field in regionPopover.contentViewController.view.subviews) {
						/// the text field contains an identifier that matches the region key
						if([field.identifier isEqualToString:keyPath]) {
							field.objectValue = [region valueForKey:keyPath];
						}
					}
				}
				if([keyPath isEqualToString:@"start"]) {
					self.start = region.start;
				}
				else if([keyPath isEqualToString:@"end"]) {
					self.end = region.end;
				}
			}
		}
	} else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}


- (void)setEnabled:(BOOL)enabled {
	if(enabled != _enabled) {
		super.enabled = enabled;
		[self updateAppearance];
	}
}


- (void)setHighlighted:(BOOL)highlighted {
	if(highlighted == self.highlighted) { // || (!highlighted && popover)) {// && NSPointInRect(self.view.clickedPoint, self.frame))) {
		/// when may get de-highlighted because our popover spawns and our view resigns first responder. We avoid that.
		return;
	}
	super.highlighted = highlighted;

	/// when we get highlighted (the user has clicked our frame), we get "edges" ready for resizing. Hence the user cannot resize before clicking us.
	/// This ensure that even if we are very close from the adjacent region,the user should always be able to grab the correct edge (and this may avoid unwanted resizing)
	/// We therefore need to reposition and get/remove tracking areas for our edges
	[self reposition];
//	[self updateTrackingArea]; // TESTING (tracking areas are updated in -reposition)
}



- (void)setStart:(float)pos {
	if(_start != pos) {
		_start = pos;
		[self reposition];
	}
}


- (void)setEnd:(float)pos {
	if(_end != pos) {
		_end = pos;
		[self reposition];
	}
}


- (float)startSize {
	MarkerOffset offset = self.offset;
	return self.start * offset.slope + offset.intercept;
}


- (float)endSize {
	MarkerOffset offset = self.offset;
	return self.end * offset.slope + offset.intercept;
}


- (void)setClicked:(BOOL)clicked {
	/// We determine where the user has clicked wrt our edges
	if(clicked == self.clicked) {
		return;
	}
	
	TraceView *view = self.view;
	
	float clickedX = view.clickedPoint.x;
	/// we set the clicked x position in our own coordinates (which must consider our offset)
	clickedPosition = ([view sizeForX:clickedX] - self.offset.intercept)/self.offset.slope;
	
	/// we determine if the user has clicked an edge
	self.clickedEdge = noEdge;	/// the default value
	if(clicked && self.highlighted) {
		if(NSPointInRect(view.clickedPoint, leftEdgeRect)) {
			self.clickedEdge = leftEdge;
		} else {
			if(NSPointInRect(view.clickedPoint, rightEdgeRect)) {
				self.clickedEdge = rightEdge;
			} else {
				self.clickedEdge = betweenEdges;
			}
		}
	}
	
	super.clicked = clicked;
	[view updateCursor];
}



- (void)setClickedEdge:(RegionEdge)edge {
	_clickedEdge = edge;
	if(edge != noEdge) {
		/// when a user clicks an edge we compute its allowed limits, which are used in -drag
		[self setLimitsForEdge:edge];
	}
}

/// Computes the limits allowed for the label edge
- (void)setLimitsForEdge:(RegionEdge)edge {
	/// This implementation is used by BinLabel and MarkerLabel, which resize the region when the user drags an edge
	BaseRange allowedRange = [self.region allowedRangeForEdge:edge];
	leftLimit = allowedRange.start;
	rightLimit = allowedRange.start + allowedRange.len;
}



-(void)setFrame:(NSRect)frame {
	_frame = frame;
}



# pragma mark - tracking area-related methods


- (void)updateTrackingArea {
	TraceView *view = self.view;
	if(!view) {
		return;
	}
	/// we set tracking areas for our edges, which are needed to show the resizing cursor
	[super updateTrackingArea];

	if(self.highlighted) {
		leftEdgeRect =  NSMakeRect(self.frame.origin.x, 0, 5, self.frame.size.height);
		rightEdgeRect =  NSMakeRect(NSMaxX(self.frame)-5, 0, 5, self.frame.size.height);
		
		leftEdgeArea = [self addTrackingAreaForRect:leftEdgeRect];
		rightEdgeArea = [self addTrackingAreaForRect:rightEdgeRect];
		NSPoint mouseLocation = view.mouseLocation;
		self.hoveredEdge = (NSPointInRect(mouseLocation, leftEdgeRect) || NSPointInRect(mouseLocation, rightEdgeRect));
		
	} else {
		leftEdgeRect = NSZeroRect;
		rightEdgeRect = NSZeroRect;
		self.hoveredEdge = NO;
	}
}


- (void)removeTrackingArea {
	TraceView *view = self.view;
	if (leftEdgeArea) {
		[view removeTrackingArea:leftEdgeArea];
		leftEdgeArea = nil;
	}
	if (rightEdgeArea) {
		[view removeTrackingArea:rightEdgeArea];
		rightEdgeArea = nil;
	}
	if(trackingArea) {
		[view removeTrackingArea:trackingArea];
		trackingArea = nil;
	}
}


- (void)mouseEntered:(NSEvent *)theEvent {
	if (theEvent.trackingArea == trackingArea) {  		/// the cursor entered the label
		[super mouseEntered:theEvent];
	} else { 											/// At his point, the mouse has entered an edge area
		self.hoveredEdge = YES;
	}
}


- (void)mouseExited:(NSEvent *)theEvent {
	 if (theEvent.trackingArea == trackingArea) {  		/// the cursor exited the label
		 [super mouseExited:theEvent];
	 } else { 											/// the cursor exited an edge
		 self.hoveredEdge = NO;
	 }
 }
	

- (void)setHoveredEdge:(BOOL)hovered {
	if(self.hoveredEdge != hovered) {
		_hoveredEdge = hovered;
		[self.view labelEdgeDidChangeHoveredState:self];
	}
}


- (void)cancelOperation:(id)sender {
	self.editState = editStateNil;
}



# pragma mark - updating or removing the region


- (NSMenu *)menu {
	/// the default menu has an item for showing the popover that allows editing our region

	if(_menu == nil) {
		_menu = [[NSMenu alloc] initWithTitle:@"edit"];
		[_menu addItemWithTitle:@"Edit Name and Range" action:@selector(spawnRegionPopover:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:@"edited"]];
		for(NSMenuItem *item in self.menu.itemArray) {
			item.target = self;
		}
	}
	return _menu;
}


NSPopover *regionPopover;	/// the popover that the user can user to edit the region. We use a single instance as just one popover should show at a time


/// The tag used to identify the controls in the regionPopover
/// These tags are set in IB
enum controlTag : NSInteger {
	startTextFieldTag = 1,
	endTextFieldTag = 2,
	nameTextFieldTag = 3,
	
} controlTag;


- (void)spawnRegionPopover:(id)sender {
	Region *region = self.region;
	if(!region || !self.view) {
		return;
	}
	if(region.name.length == 0) {
		[region autoName];	/// a proposed name should appear in the text field.
	}
	if(!regionPopover) {
		regionPopover = NSPopover.new;
		NSViewController *controller = [[NSViewController alloc] initWithNibName:@"RegionPopover" bundle:nil];
		regionPopover.contentViewController = controller;
		regionPopover.behavior = NSPopoverBehaviorTransient;
	}
	if(regionPopover.delegate != self) {
		regionPopover.delegate = (id)self;
		
		for (NSTextField *field in regionPopover.contentViewController.view.subviews) {
			NSString *identifier = field.identifier;
			if([@[@"start", @"end"] containsObject:identifier]) {
				field.delegate = (id)self;
				/// We directly change the entered value to constrain it to the allowed range of our region start or end.
				/// If we used bindings,  the region would be modified before we could do that and we wouldn't be able
				/// to compute the allowed range (since it is based on the coordinates of the region)
				field.objectValue = [region valueForKey:identifier];
			} else if(field.tag == nameTextFieldTag) {
				/// for the name, we use binding, as we can't correct an user error like we do for start and end.
				[field bind:NSValueBinding toObject:region withKeyPath:@"name" options:@{NSValidatesImmediatelyBindingOption:@YES}];
			}
		}
	}
	
	[regionPopover showRelativeToRect:self.frame ofView:self.view preferredEdge:NSMaxYEdge];

	self.highlighted = YES;			/// the popover showing makes our view resign from first responder, which de-highlight us. But it makes sense to stay highlighted
}


- (void)controlTextDidEndEditing:(NSNotification *)obj {
	/// we check if the value entered for the start or end of the region is allowed.
	NSTextField *textField = obj.object;
	NSInteger tag = textField.tag;
	if(tag != startTextFieldTag && tag != endTextFieldTag) {
		return;
	}
	Region *region = self.region;
	float position = textField.floatValue;
	if(tag == startTextFieldTag) {
		BaseRange allowedRange = [region allowedRangeForEdge:leftEdge];
		if(position < allowedRange.start || position > allowedRange.start + allowedRange.len) {
			textField.floatValue = region.start;
		} else {
			region.start = position;
		}
	} else if (tag == endTextFieldTag) {
		BaseRange allowedRange = [region allowedRangeForEdge:rightEdge];
		if(position < allowedRange.start || position > allowedRange.start + allowedRange.len) {
			textField.floatValue = region.end;
		} else {
			region.end = position;
		}
	}
}



- (void)popoverWillShow:(NSNotification *)notification {
	NSPopover *pop = notification.object;
	if(attachedPopover != pop) {
		/// if we already have a popover showing, we close it
		[attachedPopover close];
	}
	attachedPopover = pop;
	
}

- (void)popoverDidShow:(NSNotification *)notification {
	NSPopover *popover = notification.object;
	if(popover == regionPopover) {
		/// if the popover is spawn via a message sent by the contextual menu, it's text field isn't selected, so we force it.
		NSTextField *nameTextField = [regionPopover.contentViewController.view viewWithTag:3];
		[nameTextField selectText:self];
	}
}


- (void)popoverWillClose:(NSNotification *)notification {
	if(notification.object == attachedPopover && self.view.window.firstResponder != self.view) {
		self.highlighted = NO;
	}
}


- (BOOL)popoverShouldClose:(NSPopover *)popover {
	/// the popover would close even if a value is invalid and an alert is thrown.
	/// When it does, the invalid value shows in the textfield even though it is not set in the model. So we force some checks here
	/// I haven't found a better solution (see attempts below)
	
	NSError *error;
	Region *region = self.region;
	if(popover == regionPopover) {
		if(!region) {
			return YES;
		}
		for (NSTextField *textField in popover.contentViewController.view.subviews) {
			NSUInteger tag = textField.tag;
			switch (tag) {
				case startTextFieldTag: {
					NSNumber *start = @(textField.floatValue);
					[region validateValue:&start forKey:@"start" error:&error];
					break;
				}
				case endTextFieldTag: {
					NSNumber *end = @(textField.floatValue);
					[region validateValue:&end forKey:@"end" error:&error];
					break;
				}
				case nameTextFieldTag: {
					NSString *name = textField.stringValue;
					[region validateValue:&name forKey:@"name" error:&error];
					break;
				}
				default:
					break;
			}
		}
	}
	if(error) {
		return NO;
	}
	return YES;
	
}



- (void)popoverDidClose:(NSNotification *)notification {
	if(attachedPopover == notification.object) {
		attachedPopover = nil;
	}
}


- (void)drag {
	/// Default implementation used  by BinLabel and MarkerLabel, that can be used to resize or drag their region
	self.dragged = YES;

	/// We determine the position of the mouse in base pairs (trace coordinates)
	float mousePos = [self.view sizeForX:self.view.mouseLocation.x];
	float slope = self.offset.slope;
	float intercept = self.offset.intercept;
	float pos = (mousePos-intercept)/slope;    /// the position of the mouse in base pairs (in marker coordinates)
	
	if (pos < leftLimit) {
		pos = leftLimit;
	}
	if (pos > rightLimit) {
		pos = rightLimit;
	}
	
	if(self.clickedEdge == leftEdge) {
		self.start = pos;       	/// which updates our frame (see -setStart)
	} else if(self.clickedEdge == rightEdge) {
		self.end = pos;
	} else if(self.clickedEdge == betweenEdges && self.isBinLabel) {
		/// If the user has clicked between the edges, we move both edges at the same time => we move the label. We only allow that for bins
		/// this requires a bit of computation to deduce where the edges should go, since they are not at the mouse exact location
		float newStart = pos - (clickedPosition - self.region.start);
		float newEnd = pos - (clickedPosition - self.region.end);
		if (newStart < leftLimit) {
			newStart = leftLimit;
			newEnd = leftLimit + self.end - self.start;
		}
		if (newEnd > rightLimit) {
			newEnd = rightLimit;
			newStart = rightLimit - self.end + self.start;
		}
		self.start = newStart;
		self.end = newEnd;
	}
}


- (void)setDragged:(BOOL)dragged {

	/// The default  implementation updates the boundary of a region after a drag
	if(dragged != self.dragged) {
		_dragged = dragged;
		if(!dragged) {
			/// After a drag, we may have been resized (or moved, for a binLabel). We therefore transfer these changes to our region
			if(self.start != self.region.start || self.end != self.region.end) {
				[self updateRegion];
			}
		}
	}
}


/// Transfers start and end positions to that of our region.
- (void)updateRegion {
	
	Region *region = self.region;
	float start = self.start, end = self.end;
	BOOL validNewStart = NO, validNewEnd = NO, invalid = NO;
	
	if(start != region.start) {
		if(start >= leftLimit && start <= rightLimit) {
			validNewStart = YES;
		} else {
			invalid = YES;
			NSLog(@"Start position %f of %@ '%@' is out of allowed range! Not updating region.", start, region.entity.name, region.name);
		}
	}
	
	if(end != region.end) {
		if(end >= leftLimit && end <= rightLimit) {
			validNewEnd = YES;
		} else {
			invalid = YES;
			NSLog(@"End position %f of %@ '%@' is out of allowed range! Not updating region.", end, region.entity.name, region.name);
		}
	}
	
	if(invalid) {
		self.start = region.start;
		self.end = region.end;
		return;
	}
	
	if(validNewStart) {
		region.start = start;
	}
	
	if(validNewEnd) {
		region.end = end;
	}
	
	if(self.region.objectID.isTemporaryID) {
		[region autoName];
		if(self.isBinLabel) {
			[self.view labelDidUpdateNewRegion:self];
		} else if(self.isMarkerLabel) {
			[self spawnRegionPopover:self];
		}
	}
}



-(void)_updateTargetSamples:(EditState)targets withOffset:(MarkerOffset)offset {
	if(offset.slope > 1.1) {
		offset.slope = 1.1;
	} else if(offset.slope < 0.9) {
		offset.slope = 0.9;
	}
	float margin = (self.end - self.start)*0.5;

	TraceView *view = self.view;

	if(fabs(self.start - self.start * offset.slope - offset.intercept) > margin + 0.001 || fabs(self.end - self.end * offset.slope - offset.intercept) > margin + 0.001) {
		return;
	}
	
	NSSet *targetSamples;
	Chromatogram *sample = view.trace.chromatogram;
	if(view.loadedTraces.count == 1) {
		targetSamples = [NSSet setWithObject: sample];
	}
	Mmarker *marker = (Mmarker *)self.region;
	
	if(!sample || !marker) {
		return;
	}
	
	NSData *offsetCoefs = [NSData dataWithBytes:&offset length:sizeof(offset)];
	
	if(targets == editStateShownSamples) {
		if(targetSamples.count == 0) {
			targetSamples = [view.loadedTraces valueForKeyPath:@"@distinctUnionOfObjects.chromatogram"];
		}
	}
	else if(targets == editStateRun) {
		NSString *run = sample.runName;
		NSDate *runStopTime = sample.runStopTime;
		targetSamples = [sample.folder.samples filteredSetUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Chromatogram *sample, NSDictionary<NSString *,id> * _Nullable bindings) {
			return [sample.runName isEqualToString:run] && [sample.runStopTime isEqualToDate:runStopTime];
		}]];
	} else if(targets == editStateFolder) {
		SampleFolder *selectedFolder = FolderListController.sharedController.selectedFolder;
		targetSamples = selectedFolder.samples;
	} else {
		return;
	}
	
	NSArray *genotypes = [targetSamples.allObjects valueForKeyPath:@"@unionOfSets.genotypes"];
	
	genotypes = [genotypes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Genotype *genotype, NSDictionary<NSString *,id> * _Nullable bindings) {
		return genotype.marker == marker;
	}]];
	
	if(genotypes.count > 0) {
		[marker.managedObjectContext.undoManager setActionName:@"Change Marker Offset"];
		for(Genotype *genotype in genotypes) {
			genotype.offsetData = offsetCoefs;
		}
	}
}



- (void)resetBinLabels {
	
}



-(RegionLabel *)addLabelForBin:(Bin *)bin {
	return nil;
}


- (void)dealloc {
	[self stopObserving];
}

@end
