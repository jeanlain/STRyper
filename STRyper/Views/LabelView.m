//
//  LabelView.m
//  STRyper
//
//  Created by Jean Peccoud on 09/08/2022.
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



#import "LabelView.h"
#import "Panel.h"
#import "Mmarker.h"

@implementation LabelView



- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if (self) {
		labelsToReposition = NSMutableSet.new;
		self.wantsLayer = YES;
		trackingArea = [[NSTrackingArea alloc] initWithRect:self.visibleRect
													options: (NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
															  NSTrackingActiveInActiveApp | NSTrackingInVisibleRect)
													  owner:self userInfo:nil];
		[self addTrackingArea:trackingArea];
	}
	return self;
}


- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		labelsToReposition = NSMutableSet.new;
		self.wantsLayer = YES;
		trackingArea = [[NSTrackingArea alloc] initWithRect:self.visibleRect
													options: (NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
															  NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
													  owner:self userInfo:nil];
		[self addTrackingArea:trackingArea];
	}
	return self;
}


- (BOOL)layer:(CALayer *)layer shouldInheritContentsScale:(CGFloat)newScale fromWindow:(NSWindow *)window {
	return YES;
}


# pragma mark - mouse-related events


- (BOOL)acceptsFirstMouse:(NSEvent *)event {
	return YES;
}


- (void)mouseEntered:(NSEvent *)event {
	mouseIn = YES;
	[self updateCursor];
}


-(void)setMouseLocation:(NSPoint)mouseLocation {
	_mouseLocation = mouseLocation;
}


- (void)mouseDown:(NSEvent *)event {
	draggedLabel = nil;
	[self.window makeFirstResponder:self];
	self.clickedPoint = [self convertPoint:event.locationInWindow fromView:nil];
	for (ViewLabel *label in self.viewLabels) {
		/// we notify every label that the view has been clicked.
		/// We could send this message only to labels that are hovered and highlighted, but this would require maintaining arrays of such labels,
		/// for very little benefit. It's not as if there were dozens of clicks per second.
		[label mouseDownInView];
	}
}


- (void)rightMouseDown:(NSEvent *)event {
	[super rightMouseDown:event];
	[self.window makeFirstResponder:self];
	self.rightClickedPoint = [self convertPoint:event.locationInWindow fromView:nil];
	/// this calls -rightMouseDownInView on labels. We don't do here as this would not call it for ctrl-click event
}


- (void)mouseUp:(NSEvent *)event {
	draggedLabel = nil;
	self.mouseUpPoint = [self convertPoint:event.locationInWindow fromView:nil];
//	[self updateTrackingAreas];

	/// if the user has double-clicked a label
	ViewLabel *activeLabel = self.activeLabel;
	if(activeLabel && event.clickCount == 2) {
		[activeLabel doubleClickAction:self];
	}
}


- (void)rightMouseUp:(NSEvent *)event {
	self.mouseUpPoint =  [self convertPoint:event.locationInWindow fromView:nil];
}


- (NSMenu *)menuForEvent:(NSEvent *)event {
	self.rightClickedPoint = [self convertPoint:event.locationInWindow fromView:nil];
	return self.activeLabel.menu;
}



- (void)setClickedPoint:(NSPoint)point {			/// this is set on mouseDown: (and possibly on other occasions) by subclasses
	_clickedPoint = point;
	_mouseUpPoint = NSMakePoint(-10, -10);			/// this will signify that this point is no longer valid (the mouse is not up).
	_rightClickedPoint = NSMakePoint(-10, -10);

}


									
- (void)setRightClickedPoint:(NSPoint)point {
	_rightClickedPoint = point;
	_mouseUpPoint = NSMakePoint(-10, -10);
	for (ViewLabel *label in self.viewLabels) {		/// we notify every label that the view has been clicked.
		[label rightMouseDownInView];
	}
}


- (void)setMouseUpPoint:(NSPoint)point {
	_mouseUpPoint = point;
	_clickedPoint = NSMakePoint(-10, -10);
	_rightClickedPoint = NSMakePoint(-10, -10);
	for (ViewLabel *label in self.viewLabels) {
		[label mouseUpInView];
	}
}


- (void)cursorUpdate:(NSEvent *)event {
	if(!self.isMoving) {
		/// This message tends to be sent whenever the view is scrolling, which seems a waste of resources.
		[self updateCursor];
	}
}


- (void)updateCursor {
	/// overridden by subclasses
}


- (void)mouseExited:(NSEvent *)event {
	mouseIn = NO;
	/// We set a location that is outside the view bounds to make clear to labels that the mouse is no longer in the view
	/// Otherwise, some labels may get hovered when they update their tracking area.
	self.mouseLocation = NSMakePoint(-100, -100);
}

- (void)keyDown:(NSEvent *)event {
	if(!draggedLabel) {
		[super keyDown:event];
	}
}


- (void)keyUp:(NSEvent *)event {
	if(!draggedLabel) {
		[super keyUp:event];
	} 
}

# pragma mark - geometry



- (float)sizeForX:(float)xPosition {
	return xPosition/_hScale + _sampleStartSize;	/// we don't use getters for speed reasons, this method may be called very often
}


- (float)xForSize:(float)size {
	return (size - _sampleStartSize) * _hScale;
}


- (BOOL)wantsUpdateLayer {
	return YES;
}

- (void)updateLayer {
	NSArray *labels = self.needsRepositionLabels? self.markerLabels : labelsToReposition.allObjects;
	[self repositionLabels:labels];
	if(labelsToReposition.count > 0) {
		[labelsToReposition removeAllObjects];
	}
}

# pragma mark - validation and undo

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if(draggedLabel) {
		/// We forbid any action sent by a menu (via keyboard shortcut) while a label is being dragged
		/// In particular, we disable undo/redo. Overriding `keyDown:` and `keyUp:` wasn't sufficient.
		return NO;
	}
	
	if(menuItem.action == @selector(deleteSelection:)) {
		NSString *title = self.activeLabel.deleteActionTitle;
		if(title) {
			menuItem.title = title;
			menuItem.hidden = NO;				/// because the delete menu is hidden by default
			return YES;
		}
		menuItem.hidden = YES;
		return NO;
	}
	
	if(menuItem.action == @selector(undo:) || menuItem.action == @selector(redo:)) {
		/// The window itself is apparently the object that validates the undo/redo menu items.
		return [self.window validateMenuItem:menuItem];
	}
	
	return YES;
}

-(void)undo:(id)sender {
	/// To disable undo/redo menu while a label is dragged, we need to implement this method, otherwise validation will not be asked to us.
	///
	/// For reasons I can't understand, no AppKit class implements undo:, even though it is the action of the undo menu item
	/// which NSWindow is able to validate. No one can manage the message. We have to implement it.
	if(!draggedLabel) {
		[self.undoManager undo];
	}
}

-(void)redo:(id)sender {
	if(!draggedLabel) {
		[self.undoManager redo];
	}
}


# pragma mark - labels


- (NSArray<RegionLabel *> *)regionLabelsForRegions:(NSArray<Region *> *)regions reuseLabels:(NSArray<RegionLabel *> *)labels {
	
	if(regions.count == 0) {
		return NSArray.new;
	}
	
	if(labels.count == 0) {
		NSMutableArray *newLabels = [NSMutableArray arrayWithCapacity:regions.count ];
		for(Region *region in regions) {
			RegionLabel *label = [RegionLabel regionLabelWithRegion:region view:self];
			[newLabels addObject:label];
		}
		return [NSArray arrayWithArray:newLabels];
	}
	
	NSArray *reusedAsIsLabels = [labels filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RegionLabel *label, NSDictionary<NSString *,id> * _Nullable bindings) {
		return [regions indexOfObjectIdenticalTo:label.region] != NSNotFound;
	}]];
	NSInteger reusedCounts = reusedAsIsLabels.count;
	if(reusedCounts < regions.count) {
		NSArray *regionsWithLabels = [reusedAsIsLabels valueForKeyPath:@"@unionOfObjects.region"];
		NSArray *otherLabels;
		if(reusedCounts < labels.count) {
			otherLabels = reusedCounts == 0? labels : [labels arrayByRemovingObjectsIdenticalInArray:reusedAsIsLabels];
		}
		
		NSMutableArray *newLabels = [NSMutableArray arrayWithCapacity:regions.count - reusedCounts];
		NSInteger reassignedLabelsCount = 0;
		NSInteger otherLabelsCount = otherLabels.count;
		for(Region *region in regions) {
			if([regionsWithLabels indexOfObjectIdenticalTo:region] == NSNotFound) {
				RegionLabel *regionLabel;
				if(reassignedLabelsCount < otherLabelsCount) {
					regionLabel = otherLabels[reassignedLabelsCount];
					regionLabel.region = region;
					reassignedLabelsCount++;
				} else {
					regionLabel = [RegionLabel regionLabelWithRegion:region view:self];
				}
				[newLabels addObject:regionLabel];
			}
		}
		reusedAsIsLabels = [reusedAsIsLabels arrayByAddingObjectsFromArray:newLabels];
	}
	return reusedAsIsLabels;
}


- (void)repositionLabels:(NSArray *)labels  {
	if(self.hScale > 0.0 && !self.hidden) {
		BOOL notMoving = !self.isMoving;
		for (ViewLabel *label in labels) {
			[label reposition];
			if(notMoving && !label.dragged) {
				/// if the view is not moving, we reposition tracking areas
				/// (the view updates tracking areas after it stops moving and the label updates its tracking area after the drag)
				[label updateTrackingArea];
			}
		}
		self.needsRepositionLabels = NO;
	}
}


- (nullable ViewLabel *)activeLabel {
	for(ViewLabel *label in self.viewLabels) {
		if(label.highlighted) {
			return label;
		}
	}
	return nil;
}


- (void)updateTrackingAreasOf:(NSArray *)labels{
	/// We set our current mouse location as our labels use it to determine if they are still hovered within their -updateTrackingArea method.
	if(labels.count > 0) {
		NSPoint mouseLocation = self.window.mouseLocationOutsideOfEventStream;
		/// we don't use the setter as we may not want its side effects here.
		/// What matters is having an up-to-date mouse location the labels can use
		_mouseLocation = [self convertPoint:mouseLocation fromView:nil];
																			
		for(ViewLabel *label in labels) {
			[label updateTrackingArea];
		}
	}
}



- (void)setNeedsRepositionLabels:(BOOL)needsRepositionLabels {
	_needsRepositionLabels = needsRepositionLabels;
	if(needsRepositionLabels) {
		self.needsDisplay = YES;
	}
}


- (void)labelNeedsRepositioning:(ViewLabel *)viewLabel {
	if(!_needsRepositionLabels) {
		[labelsToReposition addObject:viewLabel];
		self.needsDisplay = YES;
	}
}


- (void)setNeedsUpdateLabelAppearance:(BOOL)update {
	_needsUpdateLabelAppearance = update;
	if(update) {
		self.needsDisplay = YES;
	}
}


- (void)labelDidChangeEnabledState:(ViewLabel *)label {
	
}


- (void)labelDidChangeHighlightedState:(ViewLabel *)label {
}


- (void)labelDidChangeEditState:(RegionLabel *)label {
	
}


- (void)labelDidChangeHoveredState:(ViewLabel *)label {
	if([label isKindOfClass:RegionLabel.class]) {
		RegionLabel *regionLabel = (RegionLabel *)label;
		if(label.hovered) {
			hoveredMarkerLabel = regionLabel;
		} else if(hoveredMarkerLabel == regionLabel) {
			hoveredMarkerLabel = nil;
		}
		[self updateCursor];
	}
}


- (void)labelEdgeDidChangeHoveredState:(ViewLabel *)label {
	[self updateCursor];
}


/********************** temporary test of label selection by left-right arrows

- (void)selectNext:(id)sender {
	[self selectNeighbor:YES];
}

- (void)selectPrevious:(id)sender {
	[self selectNeighbor:NO];
}

- (void)selectNeighbor:(BOOL)right {
	int increment = right? 1: -1;
	NSArray *labels = self.sortedLabels;
	for(ViewLabel *label in labels) {
		if(label.highlighted) {
			NSInteger index = [labels indexOfObjectIdenticalTo:label];
			if(index+increment <= labels.count -1 && index+increment >= 0) {
				label.highlighted = NO;
				ViewLabel *nextLabel = labels[index+increment];
				nextLabel.highlighted = YES;
				[self moveToLabel:nextLabel];
			}
			break;
		}
	}
}

- (void)moveToLabel:(ViewLabel *)label {
	
}

- (NSArray *)sortedLabels {
	return NSArray.new;
}

*********************************************/


- (void)labelDidUpdateNewRegion:(RegionLabel *)label {

	Region *region = label.region;
	if(region.managedObjectContext == temporaryContext) {
						
		if([region isKindOfClass:Mmarker.class]) {
			Mmarker *marker = (Mmarker *)region;
			[marker createGenotypesWithAlleleName: [NSUserDefaults.standardUserDefaults stringForKey:MissingAlleleName]];
		}
		
		if(temporaryContext.hasChanges) {
			NSError *error;
			[self.undoManager setActionName:[@"Add " stringByAppendingString:region.entity.name]];
			[region.managedObjectContext save:&error];
			NSManagedObjectContext *MOC = self.panel.managedObjectContext;
			if(error || !(MOC.hasChanges && [MOC save:nil])) {
				NSString *description = [NSString stringWithFormat:@"The %@ could not be added because of an error in the database", region.entity.name.lowercaseString];
				[NSApp presentError:[NSError errorWithDescription:description suggestion:@""]];
				[label removeFromView];
			}
		}
	}
}


- (void)deleteSelection:(id)sender {
	
}

# pragma mark - channels


static NSArray *_colorsForChannels;

+ (NSArray<NSColor *> *)colorsForChannels {
	if(_colorsForChannels.count < 5) {
		_colorsForChannels = @[[NSColor colorNamed:@"BlueChannelColor"], [NSColor colorNamed:@"GreenChannelColor"], [NSColor colorNamed:@"BlackChannelColor"], [NSColor colorNamed:@"RedChannelColor"], [NSColor colorNamed:@"OrangeChannelColor"]];
	}
	return _colorsForChannels;
}


+ (void)setColorsForChannels:(NSArray<NSColor *> *)colorsForChannels {
	NSArray *colors = NSArray.new;
	for(id item in colorsForChannels) {
		if([item isKindOfClass:NSColor.class]) {
			colors = [colors arrayByAddingObject:[item copy]];
		}
	}
	_colorsForChannels = colors;
}



@end
