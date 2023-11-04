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
#import "RulerView.h"
#import "FragmentLabel.h"
#import "AppDelegate.h"
#import "Mmarker.h"

@implementation LabelView

static NSArray *defaultColorsForChannels;


+ (void)initialize {
		defaultColorsForChannels = @[[NSColor colorWithCalibratedRed:0.1 green:0.1 blue:1 alpha:1],
									 [NSColor colorWithCalibratedRed:0 green:0.7 blue:0 alpha:1],
				   NSColor.darkGrayColor, NSColor.redColor, NSColor.orangeColor];
}


- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if (self && !trackingArea) {
		self.wantsLayer = YES;
		trackingArea = [[NSTrackingArea alloc] initWithRect:self.visibleRect
													options: (NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingCursorUpdate |
															  NSTrackingActiveInActiveApp | NSTrackingInVisibleRect)
													  owner:self userInfo:nil];
		[self addTrackingArea:trackingArea];
	}
	return self;
}


- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		self.wantsLayer = YES;
		trackingArea = [[NSTrackingArea alloc] initWithRect:self.visibleRect
													options: (NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingCursorUpdate |
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
	[self updateTrackingAreas];

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
	[self updateCursor];
}


- (void)updateCursor {
	// overridden by subclasses
}


- (void)mouseExited:(NSEvent *)event {
	mouseIn = NO;
	/// We set a location that is outside the view bounds to make clear to labels that the mouse is no longer in the view
	/// Otherwise, some labels may get hovered when they update their tracking area.
	self.mouseLocation = NSMakePoint(-100, -100);
}

# pragma mark - geometry



- (float)sizeForX:(float)xPosition {
	return xPosition/_hScale + _sampleStartSize;	/// we don't use getters for speed reasons, this method may be called very often
}


- (float)xForSize:(float)size {
	return (size - _sampleStartSize) * _hScale;
}


- (void)setFrameSize:(NSSize)newSize {
	if(!NSEqualSizes(self.frame.size, newSize)) {
		[super setFrameSize:newSize];
		if(self.hidden) {
			return;
		}
		/// we determine if the view is resized via animation. If so, we reposition labels immediately.
		/// If we do during -layout, their movements don't follow the animation nicely.
		if(NSAnimationContext.currentContext.allowsImplicitAnimation) {
			[self repositionLabels:self.repositionableLabels allowAnimation:YES];
		} else {
			self.needsLayoutLabels = YES;
		}
	}
}


- (void)layout {
	[super layout];
	if(self.needsLayoutLabels) {
		[self repositionLabels:self.repositionableLabels allowAnimation:NO];
	}
}


# pragma mark - labels

- (void)repositionLabels:(NSArray *)labels allowAnimation:(BOOL)allowAnimate {
	if(self.hScale > 0.0 && !self.hidden) {
		for (ViewLabel *label in labels) {
			label.animated = allowAnimate;
			[label reposition];
			label.animated = YES;
		}
		self.needsLayoutLabels = NO;
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



- (void)setNeedsLayoutLabels:(BOOL)needsLayoutLabels {
	_needsLayoutLabels = needsLayoutLabels;
	if(needsLayoutLabels) {
		self.needsLayout = YES;
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
		
		/// as the label is already present and the region will appear in the view context, we tell us to not recreate region labels (which our subclasses do normally)
		/// this will help to maintain the highlighted state of the label
		doNotCreateLabels = YES;
		BOOL saved = NO;
		if(temporaryContext.hasChanges) {
			saved = [region.managedObjectContext save:nil];
		}

		doNotCreateLabels = NO;
		if(saved) {
			/// we need to materialize the region in the view context, to attach it to the label.
			Region *theRegion = [self.panel.managedObjectContext objectWithID:region.objectID];
			if(theRegion.objectID.isTemporaryID) {
				[theRegion.managedObjectContext obtainPermanentIDsForObjects:@[theRegion] error:nil];
			}
			if(theRegion) {
				label.region = theRegion;
			}
			[self.undoManager setActionName:[@"Add " stringByAppendingString:region.entity.name]];
		} else {
			NSString *description = [NSString stringWithFormat:@"The %@ could not be added because of an error in the database", region.entity.name.lowercaseString];
			[NSApp presentError:[NSError errorWithDescription:description suggestion:@""]];
			[label removeFromView];
		}
	}
}


- (void)autoscrollWithDraggedLabel:(ViewLabel *)draggedLabel {
	/// overridden
}


# pragma mark - channels


+(NSArray<NSColor *> *)defaultColorsForChannels {
	/// the index of the color correspond to the channels fro 0 to 4;
	return defaultColorsForChannels;
}


- (NSArray<NSColor *> *)colorsForChannels {
	if(_colorsForChannels.count < 5) {
		_colorsForChannels = [self.class defaultColorsForChannels];
	}
	return _colorsForChannels;
}


- (void)setColorsForChannels:(NSArray<NSColor *> *)colorsForChannels {
	NSArray *colors = NSArray.new;
	for(id item in colorsForChannels) {
		if([item isKindOfClass:NSColor.class]) {
			colors = [colors arrayByAddingObject:[item copy]];
		}
	}
	_colorsForChannels = colors;
	self.needsDisplay = YES;
}



@end
