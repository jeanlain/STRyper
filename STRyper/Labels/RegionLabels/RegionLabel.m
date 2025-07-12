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
#import "MarkerLabel.h"
#import "BinLabel.h"
#import "TraceViewMarkerLabel.h"
#import "NewMarkerPopover.h"


@interface RegionLabel ()

@property (weak) NSPopover *attachedPopover;

@end


@implementation RegionLabel

@synthesize hoveredEdge = _hoveredEdge;


#pragma mark - initialization and base attributes setting

/// Pointier to observe some keys of our region to update when they change
static void * const regionStartChangedContext = (void*)&regionStartChangedContext;
static void * const regionEndChangedContext = (void*)&regionEndChangedContext;
static void * const regionEditStateChangedContext = (void*)&regionEditStateChangedContext;
static void * const regionNameChangedContext = (void*)&regionNameChangedContext;
static void * const popoverDelegateChangedContext = (void*)&popoverDelegateChangedContext;
static NSManagedObjectContext *temporaryContext;


+ (nullable __kindof RegionLabel*)regionLabelWithRegion:(Region *)region view:(__kindof LabelView *)view {
	RegionLabel *label;
	if([region isKindOfClass:Mmarker.class]) {
		if([view isKindOfClass:TraceView.class]) {
			label = TraceViewMarkerLabel.new;
		} else {
			label = MarkerLabel.new;
		}
	} else {
		label = BinLabel.new;
	}
	if(label) {
		label.view = view;
		label.region = region;
	}
	
	return label;
}


+ (nullable __kindof RegionLabel*)regionLabelWithNewRegionByDraggingInView:(__kindof LabelView *)view
																	 error:(NSError * _Nullable __autoreleasing *)error {
	float position = [view sizeForX:view.mouseLocation.x];         	/// the mouse position in base pairs
	float clickedPosition =  [view sizeForX:view.clickedPoint.x];   /// the original clicked position in base pairs

	Panel *panel;
	Mmarker *marker;
	CodingObject *parentObject;
	if(![view isKindOfClass:TraceView.class]) {
		panel = view.panel;
		parentObject = panel;
	} else {
		for(MarkerLabel *label in view.markerLabels) {
			if(label.start <= clickedPosition && label.end >= clickedPosition) {
				marker = label.region;
				parentObject = marker;
				MarkerOffset offset = label.offset;
				position = (position - offset.intercept) / offset.slope;
				clickedPosition = (clickedPosition - offset.intercept) / offset.slope;
				break;
			}
		}
	}
	if(!parentObject) {
		return nil;
	}
		
	float start = MIN(position, clickedPosition);
	float end = MAX(clickedPosition, position);
	
	temporaryContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];

	NSError *databaseError;
	/// we add the new region in a temporary context, as the region is not in its final state until mouseUp, and changes should not be undoable
	if(parentObject.objectID.isTemporaryID) {
		[parentObject.managedObjectContext obtainPermanentIDsForObjects:@[parentObject] error:&databaseError];
	}
	temporaryContext.parentContext = parentObject.managedObjectContext;
	/// we materialize the parent object in this context, as the new region must be added to it
	parentObject = [temporaryContext existingObjectWithID:parentObject.objectID error:&databaseError];
	
	if(databaseError || parentObject.managedObjectContext != temporaryContext) {
		if(error != NULL) {
			*error = databaseError;
		}
		return nil;
	}
	Region *newRegion;
	if(panel) {
		panel = (Panel *)parentObject;
		ChannelNumber channel = [(TraceView *)view channel];
		newRegion = [[Mmarker alloc] initWithStart:start end:end channel:channel ploidy:diploid panel:panel];
	} else if (marker) {
		marker = (Mmarker *)parentObject;
		newRegion = [[Bin alloc] initWithStart:start end:end marker:marker];
	}
	if(!newRegion) {
		return nil;
	}
	/// we give a blank name. Only on mouseUp the region will get its final name (we use a space as an empty name causes issues)
	newRegion.name = @" ";

	RegionLabel *label = [self regionLabelWithRegion:newRegion view:view];
	
	/// we highlight the label and the correct edge to allow immediate sizing (see below)
	label.highlighted = YES;
	label.clicked = YES;
	label.clickedEdge = position < clickedPosition? leftEdge: rightEdge;
	return label;
}


- (__kindof RegionLabel *)labelWithNewBinByDraggingWithError:(NSError * _Nullable __autoreleasing *)error {
	return nil;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_offset = MarkerOffsetNone;
		layer = CALayer.new;
		layer.delegate = self;
		layer.opaque = YES;
		if(![self isKindOfClass:TraceViewMarkerLabel.class]) {
			bandLayer = CALayer.new;
			bandLayer.delegate = self;
			bandLayer.opaque = YES;

			stringLayer = CATextLayer.new;
			stringLayer.contentsScale = 2.0;
			stringLayer.delegate = self;
			stringLayer.drawsAsynchronously = YES;  			/// maybe that helps a bit (not noticeable)
			stringLayer.font = (__bridge CFTypeRef _Nullable)[NSFont labelFontOfSize:8.5];
			stringLayer.foregroundColor = NSColor.textColor.CGColor;
		}
	}
	return self;
}


- (void)setRegion:(__kindof Region *)region {
	if(_region) {
		[_region removeObserver:self forKeyPath:regionStartKey];
		[_region removeObserver:self forKeyPath:regionEndKey];
		if(!self.isBinLabel) {
			[_region removeObserver:self forKeyPath:regionEditStateKey];
		}
		if(![self isKindOfClass:TraceViewMarkerLabel.class]) {
			[_region removeObserver:self forKeyPath:regionNameKey];
		}
		[self.attachedPopover close];
		self.attachedPopover = nil;
	}
	_region = region;
	
	if(region) {
		/// We observe the region rather than self for @"region.start" (in `init`) for instance, because that causes crashes when undoing
		/// the deletion of a marker, for reasons I could not identify (observers were properly removed in dealloc).

		[region addObserver:self forKeyPath:regionStartKey
					options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					context:regionStartChangedContext];
		[region addObserver:self forKeyPath:regionEndKey
					options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					context:regionEndChangedContext];
		if(!self.isBinLabel) {
			[region addObserver:self forKeyPath:regionEditStateKey
						options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
						context:regionEditStateChangedContext];
		}
		if(![self isKindOfClass:TraceViewMarkerLabel.class]) {
			/// This class of label doesn't show the name of the region.
			[region addObserver:self forKeyPath:regionNameKey
						options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
						context:regionNameChangedContext];
		}
	}
}



- (BOOL)highlightedOnMouseUp {
	/// These labels are only highlighted on mouseUp, to avoid unwanted dragging (of bins, in particular).
	/// The user has to select them, release the mouse, and then drag edges or the whole bin
	return NO;
}


- (id)representedObject {
	return self.region;
}



-(void) removeFromView {
	if(_attachedPopover) {
		[self.attachedPopover close];
		self.attachedPopover = nil;
	}
	[bandLayer removeFromSuperlayer];		/// the band layer may not be in the same view as the `layer`, so we remove it from its parent separately

	[super removeFromView];
}


- (void)updateForTheme {
	stringLayer.foregroundColor = NSColor.textColor.CGColor;
}

# pragma mark - reacting to region and view changes, geometry updates

- (void)updateStringLayer {
	NSString *name = self.region.name;
	if(name) {
		stringLayer.string = name;
		CGSize size = stringLayer.preferredFrameSize;
		stringLayer.bounds = CGRectMake(0, 0, size.width, size.height);
	}
}


- (void)updateAppearance {
	/// A region label has different tracking areas depending on its state (highlighted in particular).
	if(needsUpdateTrackingAreas) {
		layer.borderWidth = _highlighted? 1.0 : 0.0;
		[self updateTrackingArea];
		needsUpdateTrackingAreas = NO;
	}
	
	if(needsUpdateString) {
		[self updateStringLayer];
		if(!self.view.needsRepositionLabels) {
			[self layoutInternalLayers]; /// The change in layer size requires this.
		}
		needsUpdateString = NO;
	}
}


-(void)layoutInternalLayers {
	/// overridden
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if(object == _region && _region.isDeleted) {
		return;
	}
	if(context == regionEditStateChangedContext) {
		self.editState = self.region.editState;
	} else if(context == regionNameChangedContext){
		if(self.isBinLabel) {
			[self updateStringLayer];
			/// If the bin name change, we ask to reposition the parent label to avoid overlap with other bin names.
			TraceViewMarkerLabel *parentLabel = [(BinLabel *)self parentLabel];
			if(parentLabel) { /// which is `nil` if the label was just created and got a new region, but
							  /// the parent label will be repositioned anyway.
				[self.view labelNeedsRepositioning:parentLabel];
			}
		} else {
			/// For a marker name, we defer the update
			needsUpdateString = YES;
			self.needsUpdateAppearance = YES;
		}
	} else  if(context == regionStartChangedContext || context == regionEndChangedContext) {
		Region *region = object;
		/// we close any popover we show if it is not the one changing the attributes of the region.
		if(self.attachedPopover && self.attachedPopover != regionPopover) {
			[self.attachedPopover performClose:self];
		}
		if(context == regionStartChangedContext) {
			self.start = region.start;
		} else if(context == regionEndChangedContext) {
			self.end = region.end;
		}
	} else if(context == popoverDelegateChangedContext) {
		if(_attachedPopover.delegate != self) {
			self.attachedPopover = nil;
		}
	}
}


- (void)setStart:(float)pos {
	if(_start != pos) {
		_start = pos;
		[self.view labelNeedsRepositioning:self];
	}
}


- (void)setEnd:(float)pos {
	if(_end != pos) {
		_end = pos;
		[self.view labelNeedsRepositioning:self];
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
	NSPoint clickedPoint = view.clickedPoint;
	/// we determine if the user has clicked an edge
	/// Computing edge rects is redundant if the label was already highlighted, but required if it was not
	NSRect frame = self.frame;
	leftEdgeRect =  NSMakeRect(frame.origin.x, 0, 5, frame.size.height);
	rightEdgeRect =  NSMakeRect(NSMaxX(frame)-5, 0, 5, frame.size.height);
	self.clickedEdge = noEdge;	/// the default value
	if(clicked && self.highlighted) {
		if(NSPointInRect(clickedPoint, leftEdgeRect)) {
			self.clickedEdge = leftEdge;
		} else {
			if(NSPointInRect(clickedPoint, rightEdgeRect)) {
				self.clickedEdge = rightEdge;
			} else {
				self.clickedEdge = betweenEdges;
			}
		}
	}
	if(self.hoveredEdge & !clicked) {
		NSPoint mouseLocation = view.mouseLocation;
		/// If the mouse exits an edge tracking area while still clicked (i.e., dragged), no mouseExit even is sent,
		/// so hoveredEdge would not have been set to NO as it should.
		self.hoveredEdge = NSPointInRect(mouseLocation, leftEdgeRect)  || NSPointInRect(mouseLocation, rightEdgeRect);
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

- (void)setHighlighted:(BOOL)highlighted {
	if(highlighted != _highlighted) {
		super.highlighted = highlighted;
		needsUpdateTrackingAreas = YES;
	}
}


- (void)updateTrackingArea {
	TraceView *view = self.view;
	if(view) {
		BOOL highlighted = self.highlighted;
		NSRect frame = NSInsetRect(regionRect, -2, 0);
		/// when highlighted, the frame gets a bit wider
		/// to avoid deselecting the label when the user clicks an edge for resizing.
		self.frame = highlighted? frame: regionRect;
		[super updateTrackingArea];
		
		if(highlighted) {
			leftEdgeRect =  NSMakeRect(frame.origin.x, 0, 5, frame.size.height);
			rightEdgeRect =  NSMakeRect(NSMaxX(frame)-5, 0, 5, frame.size.height);
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
}


- (void)removeTrackingArea {
	TraceView *view = self.view;
	if (leftEdgeArea) {
		[view removeTrackingArea:leftEdgeArea];
	}
	if (rightEdgeArea) {
		[view removeTrackingArea:rightEdgeArea];
	}
	if(trackingArea) {
		[view removeTrackingArea:trackingArea];
	}
}


- (void)mouseEntered:(NSEvent *)theEvent {
	NSTrackingArea *trackingArea = theEvent.trackingArea;
	if (trackingArea == self->trackingArea) {
		[super mouseEntered:theEvent];
	} else if(trackingArea == leftEdgeArea || trackingArea == rightEdgeArea) {
		self.hoveredEdge = YES;
	}
}


- (void)mouseExited:(NSEvent *)theEvent {
	NSTrackingArea *trackingArea = theEvent.trackingArea;
	 if (trackingArea == self->trackingArea) {
		 [super mouseExited:theEvent];
	 } else if(trackingArea == leftEdgeArea || trackingArea == rightEdgeArea) {
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
	if(!_dragged) {
		self.editState = editStateNil;
	}
}



# pragma mark - updating or removing the region


- (NSMenu *)menu {
	/// the default menu has an item for showing the popover that allows editing our region

	if(_menu == nil) {
		_menu = NSMenu.new;
		[_menu addItemWithTitle:@"Edit Name and Range" action:@selector(spawnRegionPopover:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:ACImageNameEdited]];
		for(NSMenuItem *item in self.menu.itemArray) {
			item.target = self;
		}
	}
	return _menu;
}


NSPopover *regionPopover;	/// the popover that the user can user to edit the region. We use a single instance as just one popover should show at a time



- (void)spawnRegionPopover:(id)sender {
	Region *region = self.region;
	if(!region || !self.view) {
		return;
	}

	if(!regionPopover) {
		regionPopover = NSPopover.new;
		NSViewController *controller = [[NSViewController alloc] initWithNibName:@"RegionPopover" bundle:nil];
		regionPopover.contentViewController = controller;
		regionPopover.behavior = NSPopoverBehaviorTransient;
	}
	if(regionPopover.delegate != self) {
		regionPopover.delegate = self;
		for (NSTextField *field in regionPopover.contentViewController.view.subviews) {
			NSString *identifier = field.identifier;
			if([@[regionStartKey, regionEndKey, regionNameKey] containsObject:identifier]) {
				field.delegate = self;
				[field bind:NSValueBinding toObject:region withKeyPath:identifier 
					options:@{NSValidatesImmediatelyBindingOption:@YES}];
			}
		}
	}
	
	[regionPopover showRelativeToRect:self.frame ofView:self.view preferredEdge:NSMaxYEdge];
}


- (void)setAttachedPopover:(NSPopover *)attachedPopover {
	/// We observe the delegate of the attached popover, as a delegate that is different from the label means that the popover should
	/// no longer be attached to it (it will be attached to another label). Several labels with the same attached popover will conflict in positioning the popover.
	/// This currently is a safety measure, as the popover closes (setting this property to `nil`) before another label spawns it (due to the double click).
	if(_attachedPopover != attachedPopover) {
		if(_attachedPopover) {
			[_attachedPopover removeObserver:self forKeyPath:@"delegate"];
		}
		_attachedPopover = attachedPopover;
		if(_attachedPopover) {
			[_attachedPopover addObserver:self forKeyPath:@"delegate"
								  options:NSKeyValueObservingOptionNew
								  context:popoverDelegateChangedContext];
		}
	}
}


- (void)controlTextDidEndEditing:(NSNotification *)obj {
	NSTextField *textField = obj.object;
	NSString *ID = textField.identifier;
	if([ID isEqualToString:regionNameKey]) {
		[self.view.undoManager setActionName:self.isBinLabel? @"Rename Bin" : @"Rename Marker"];
	} else if([@[regionStartKey, regionEndKey] containsObject:ID]) {
		[self.view.undoManager setActionName:self.isBinLabel? @"Resize Bin" : @"Resize Marker"];
	}
}



- (void)popoverWillShow:(NSNotification *)notification {
	NSPopover *pop = notification.object;
	self.attachedPopover = pop;
}


- (void)popoverDidShow:(NSNotification *)notification {
	NSPopover *popover = notification.object;
	if(popover == regionPopover) {
		/// if the popover is spawn via a message sent by the contextual menu, it's text field isn't selected, so we force it.
		NSTextField *nameTextField = [popover.contentViewController.view viewWithTag:3];
		[nameTextField selectText:self];
	}
}


- (void)popoverWillClose:(NSNotification *)notification {
	if(notification.object == _attachedPopover) {
		self.attachedPopover = nil;
		if(self.view.window.firstResponder != self.view) {
			self.highlighted = NO;
		}
	}
}



- (void)drag {
	/// Default implementation used by BinLabel and MarkerLabel, which resizes or moves their region
	
	TraceView *view = self.view;
	NSPoint mouseLocation = view.mouseLocation;

	/// We determine the position of the mouse in base pairs (trace coordinates)
	float mousePos = [view sizeForX:mouseLocation.x];
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
		self.dragged = YES;
		self.start = pos;
	} else if(self.clickedEdge == rightEdge) {
		self.dragged = YES;
		self.end = pos;
	} else if(self.clickedEdge == betweenEdges && self.isBinLabel) {
		if(!self.dragged) {
			/// We do not start the drag if the user has not dragged the mouse for at least 5 points.
			/// This avoids moving the bin after a simple click
			if(fabs(mouseLocation.x - view.clickedPoint.x) < 2) {
				return;
			}
			self.dragged = YES;
		}
		
		/// If the user has clicked between the edges, we move both edges at the same time => we move the label. We only allow that for bins
		/// this requires a bit of computation to deduce where the edges should go, since they are not at the mouse exact location
		TraceView *view = self.view;
		MarkerOffset offset = self.offset;
		float clickedPosition = ([view sizeForX:view.clickedPoint.x] - offset.intercept)/offset.slope;
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
	[super drag];
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
			[self updateTrackingArea]; /// Since tracking areas are not updated during the drag.
			
			/// If the mouse is moving quickly after the drag session ended, it may exit tracking areas without mouseExited: being sent. Hence, the cursor will not update.
			/// I suppose the tracking areas are not "ready" to react yet (an appkit bug?)
			/// To reduce the risk of this happening, we send this message:
			[self performSelector:@selector(_updateHoveredState) withObject:nil afterDelay:0.05];
		}
	}
}


-(void)_updateHoveredState {
	NSPoint mouseLocation = self.view.mouseLocation;
	self.hovered = NSPointInRect(mouseLocation, self.frame);
	self.hoveredEdge = (NSPointInRect(mouseLocation, leftEdgeRect) || NSPointInRect(mouseLocation, rightEdgeRect));
}


/// Transfers start and end positions to that of the region.
- (void)updateRegion {
	
	Region *region = self.region;
	float start = self.start, end = self.end;
	if(start == region.start && end == region.end) {
		return;
	}
	
	NSError *databaseError;
	NSManagedObjectContext *MOC = region.managedObjectContext;
	BOOL newRegion = MOC == temporaryContext; /// When the region is in a temporary context, it means it has been just created via click & drag
	if(!newRegion) {
		if(MOC.hasChanges) {
			[MOC save:&databaseError];
		}
		
		/// We will update the region coordinates on a child context to validate them.
		/// This is because we have to update both start and end for the validation to work.
		/// And we don't want to change the coordinates in the view context in case they are invalid. This would generate undo actions, among other nuisances.
		MOC = AppDelegate.sharedInstance.newChildContextOnMainQueue;
		region = [MOC existingObjectWithID:region.objectID error:&databaseError];
	}
	
	if(!databaseError) {
		float originalStart = region.start, originalEnd = region.end;
		region.start = start;
		region.end = end;
		if(![region validateForUpdate:nil]) {
			/// We don't throw the error at the user because it wouldn't be their fault. This would be a programmer error (we could throw an exception to catch...)
			NSLog(@"%@ '%@' is out of allowed range! Not updating region.", region.entity.name, region.name);
			if(newRegion) {
				[self removeFromView]; 
			} else {
				/// We restore the original coordinates, so that the drag is undone.
				self.start = originalStart;
				self.end = originalEnd;
			}
			return;
		}
		
		if(newRegion) {
			[region autoName];
			if(self.isBinLabel) {
				[self.view labelDidUpdateNewRegion:self];
			}
			[self performSelector:@selector(spawnRegionPopover:) withObject:self afterDelay:0.05];
			
		} else if(MOC.hasChanges) {
			[MOC save:&databaseError];
		}
	}
	if(databaseError) {
		/// We undo the drag.
		self.start = region.start;
		self.end = region.end;
		NSString *description = [NSString stringWithFormat:@"The %@ could not be modified because of a database error.", region.entity.name];
		databaseError = [NSError errorWithDescription:description suggestion:@"You may try to restart the application."];
		[[NSAlert alertWithError:databaseError] runModal];
	} else {
		NSString *actionName = self.isBinLabel? @"Edit Bin" : @"Resize Marker";
		[self.view.undoManager setActionName:actionName];
	}
}



-(BOOL)_updateOffset:(MarkerOffset)offset {
	if(offset.slope > 1.1) {
		offset.slope = 1.1;
	} else if(offset.slope < 0.9) {
		offset.slope = 0.9;
	}
	float margin = (self.end - self.start)*0.5;
	if(fabs(self.start - self.start * offset.slope - offset.intercept) > margin + 0.001 || fabs(self.end - self.end * offset.slope - offset.intercept) > margin + 0.001) {
		return NO;
	}

	TraceView *view = self.view;
	NSArray *targetSamples = [view.loadedTraces valueForKeyPath:@"@distinctUnionOfObjects.chromatogram"];
	Mmarker *marker = (Mmarker *)self.region;
	
	if(!targetSamples || !marker) {
		return NO;
	}
	
	NSArray<Genotype *> *genotypes = [targetSamples valueForKeyPath:@"@unionOfSets.genotypes"];
	
	genotypes = [genotypes filteredArrayUsingBlock:^BOOL(Genotype*  _Nonnull genotype, NSUInteger idx) {
		return genotype.marker == marker;
	}];
	
	if(genotypes.count > 0) {
		NSData *offsetCoefs = [NSData dataWithBytes:&offset length:sizeof(offset)];
		[self.view.undoManager setActionName:@"Change Marker Offset"];
		for(Genotype *genotype in genotypes) {
			genotype.offsetData = offsetCoefs;
		}
		return YES;
	}
	return NO;
}



- (void)dealloc {
	self.region = nil; /// This is crucial to remove observers.
}

@end
