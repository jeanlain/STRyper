//
//  BinLabel.m
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


#import "BinLabel.h"
#import "TraceView.h"

@implementation BinLabel

- (BOOL)isBinLabel {
	return YES;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		_enabled = NO;			/// bin labels are disabled by default
		_offset = MarkerOffsetNone;
		
		layer = CALayer.new;
		layer.actions = @{NSStringFromSelector(@selector(backgroundColor)):NSNull.null,
						  NSStringFromSelector(@selector(borderWidth)):NSNull.null};
		
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
		
		layer.borderColor = NSColor.blackColor.CGColor;
		
		/// our bandLayer is a thin rectangle behind the bin name, which appears at its center.
		/// We use two layers instead of just a CATextLayer with kCAAlignmentCenter to center the text. Changing the bounds of a CATextLayer kills performance
		/// Instead, we never modify the bounds of the stringLayer, only those of the bandLayer
		bandLayer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
		
		bandLayer.anchorPoint = CGPointMake(0.5, 1);		/// this helps to position that layer within its parent (same for the following instruction)
		bandLayer.zPosition = 1.0;							/// because for some unclear reasons, this layer may sometimes show behind trace
		stringLayer.fontSize = 8.5;
		layer.geometryFlipped = YES;
		[bandLayer addSublayer:stringLayer];
		
		disabledColor = [NSColor colorWithCalibratedWhite:0.8 alpha:1.0];
		defaultColor = [NSColor colorWithCalibratedWhite:0.8 alpha:1.0];     	/// default color is grey
		hoveredColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];		/// darker gray when hovered
		activeColor = hoveredColor;
		edgeColor = NSColor.blackColor;
	}
	return self;
}


- (void)setView:(TraceView *)view {
	super.view = view;
	if(view && layer) {
		[view.backgroundLayer addSublayer:layer];
		[view.layer addSublayer:bandLayer];
	}
}


- (void)updateAppearance {
	[super updateAppearance];
	if(self.hovered == bandLayer.isHidden) {
		/// if a bin label is hovered, its name must show,
		self.animated = NO;
		[self repositionInternalLayers];
		self.animated = YES;
	}
}


- (void)setHidden:(BOOL)hidden {
	if(self.hidden != hidden) {
		bandLayer.hidden = hidden;	/// for these labels, the bandlayer is not hosted by the layer, so we must hide/show it separately
		super.hidden = hidden;
	}
}

- (void)reposition {
	TraceView *view = self.view;
	float hScale = view.hScale;
	if(hScale <= 0 || self.hidden) {
		return;
	}
	

	float startSize = self.startSize;
	float endSize = self.endSize;
	float startX = [view xForSize:startSize];     /// to get our frame, we convert our position in base pairs to points (x coordinates)	
	regionRect = NSMakeRect(startX, 0, (endSize - startSize) * hScale, NSMaxY(view.bounds));
	
	/// When highlighted, our frame (used by the tracking area) gets a bit wider so that the user can more easily click an edge to resize us
	self.frame = self.highlighted? NSInsetRect(regionRect, -2, 0) : regionRect;
	
	/// The layer is a bit taller than its host view to  hide the bottom and top edges.
	layer.frame = CGRectInset(regionRect, 0, -2);
	
	[self repositionInternalLayers];
	
	if(!view.isMoving && self.enabled && !self.dragged) {
		[self updateTrackingArea];  
	}
}


/// Repositions the layers showing the bin name
-(void) repositionInternalLayers {
	/// we don't show the bandLayer (hence the name) if the bin label is too narrow.
	if (regionRect.size.width <= stringLayer.bounds.size.width/2 && !self.hovered) {
		bandLayer.hidden = YES;
	} else {
		bandLayer.hidden = NO;
		CGRect rect = stringLayer.bounds;
		if(rect.size.width < regionRect.size.width) {
			rect.size.width = regionRect.size.width;
		}
		bandLayer.bounds = rect;
		bandLayer.position = CGPointMake(NSMidX(regionRect), NSMaxY(regionRect));
		stringLayer.position = CGPointMake(NSMidX(bandLayer.bounds), NSMidY(bandLayer.bounds));
	}
}


-(void)setFrame:(NSRect)frame {
	_frame = frame;
}


- (NSMenu *)menu {
	_menu = super.menu;
	if(_menu.itemArray.count < 2) {
		/// we just add a menu item allowing to delete our bin
		[_menu addItemWithTitle:@"Delete" action:@selector(deleteAction:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:@"trash"]];
		for(NSMenuItem *item in self.menu.itemArray) {
			item.target = self;
		}
	}
	return _menu;
}


- (void)deleteAction:(id)sender {
	/// We delete our bin
	if (self.highlighted) {
		NSManagedObjectContext *MOC = self.region.managedObjectContext;
		if(!MOC) {
			return;
		}
		[MOC deleteObject:self.region];		/// this triggers the recreation of labels by the view, which will deallocate us
		[self.view.undoManager setActionName: self.deleteActionTitle];
		self.view = nil; 									/// this removes us from the view because when our region is removed, we may still exist in the view and interfere.
	}
}


- (nullable NSString *)deleteActionTitle {
	return @"Delete Bin";
}


- (void)doubleClickAction:(id)sender {
	/// when double-clicked, we show the popover that allows the user to edit our name, start and end positions
	[self spawnRegionPopover:sender];
}



@end
