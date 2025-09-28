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
#import "TraceViewMarkerLabel.h"

@interface BinLabel ()

/// Whether the bin name should be hidden to avoid overlap with others.
/// `YES` may not mean that the bin name is hidden, as it must show when the label is `hovered` / `highlighted`.
/// We use this properly to determine if we should hide the bin name when the label is no longer hovered or `highlighted`
@property (nonatomic) BOOL binNameHidden;

@end


@implementation BinLabel

@synthesize binNameHidden = _binNameHidden;

- (BOOL)isBinLabel {
	return YES;
}


- (instancetype)init {
	self = [super init];
	if (self) {
		_enabled = NO;			/// bin labels are disabled by default
		
		layer.zPosition = -0.5; /// To show being traces in the host view.
		layer.geometryFlipped = YES; /// This helps placing the bandLayer at the top of the layer.
		stringLayer.fontSize = 8.5;
		stringLayer.alignmentMode = kCAAlignmentCenter;
				
		/// our bandLayer is a thin rectangle behind the bin name, which appears at its center. It is at least as wide as the bin.
		/// We use two layers instead of just a CATextLayer with kCAAlignmentCenter to center the text. Changing the bounds of a CATextLayer kills performance.
		/// Instead, we never modify the bounds of the stringLayer (unless the text changes), only those of the bandLayer
		bandLayer.anchorPoint = CGPointMake(0.5, 1);		/// this helps to position that layer within its parent (same for the following instruction)
		bandLayer.zPosition = 1.0;							/// because for some unclear reasons, this layer may sometimes show behind traces
	}
	
	return self;
}


- (void)setView:(TraceView *)view {
	super.view = view;
	if(view && layer) {
		if(!view.needsUpdateLabelAppearance) {
			layer.backgroundColor = view.binLabelColor;
			layer.borderColor = view.regionLabelEdgeColor;
			bandLayer.backgroundColor = view.binNameBackgroundColor;
			bandLayer.borderColor = view.hoveredBinLabelColor;
		}
		stringLayer.foregroundColor = NULL;
		stringLayer.foregroundColor = view.labelStringColor;
		[view.backgroundLayer addSublayer:bandLayer];
	}
}


- (void)setParentLabel:(TraceViewMarkerLabel *)parentLabel {
	if(_parentLabel != parentLabel) {
		_parentLabel = parentLabel;
		[parentLabel._layer addSublayer:layer];
	}
}


- (void)setStart:(float)start {
	if(start != _start) {
		_start = start;
		if(_parentLabel) {
			[self.view labelNeedsRepositioning:_parentLabel];
		}
	}
}


- (void)setEnd:(float)end {
	if(end != _end) {
		_end = end;
		if(_parentLabel) {
			[self.view labelNeedsRepositioning:_parentLabel];
		}
	}
}


- (MarkerOffset)offset {
	return _parentLabel.offset;
}


- (void)updateAppearance {
	layer.backgroundColor = NULL;
	bandLayer.backgroundColor = NULL;
	TraceView *view = self.view;
	BOOL hovered = self.hovered;
	BOOL highlighted = self.highlighted;
	layer.backgroundColor = (hovered || highlighted)? view.hoveredBinLabelColor : view.binLabelColor;
	bandLayer.backgroundColor = (hovered || highlighted)? view.hoveredBinNameBackgroundColor : view.binNameBackgroundColor;
	bandLayer.borderWidth = (hovered || highlighted)? 1.0 : 0.0;
	
	/// We determine of the visibility of the bin name should change. It must be visible if the label became hovered or highlighted.
	BOOL hideBinName = (hovered || highlighted)? NO : _binNameHidden;
	if(hideBinName != bandLayer.isHidden) {
		if(_binNameHidden) {
			/// Which means the bin name must show.
			bandLayer.hidden = NO;
		}
		/// To avoid overlaps of bin names, we arrange other labels.
		/// We do it immediately rather than asking the view to reposition the parent label, because the call of this method is already deferred
		/// and this should be executed only once per cycle (when the user hovers a label or selects/deselects it).
		[self.class arrangeLabels:_parentLabel.binLabels withRepositioning:NO];
	}
	bandLayer.zPosition = hovered? 1.11 : highlighted? 1.1 : 1.0;
	[super updateAppearance];
}


- (void)updateForTheme {
	TraceView *view = self.view;
	layer.borderColor = view.regionLabelEdgeColor;
	layer.backgroundColor = self.hovered? view.hoveredBinLabelColor : view.binLabelColor;
	bandLayer.backgroundColor = view.binNameBackgroundColor;
	bandLayer.borderColor = view.hoveredBinLabelColor;
	stringLayer.foregroundColor = NULL;
	stringLayer.foregroundColor = view.labelStringColor;
}


- (void)setHidden:(BOOL)hidden {
	if(self.hidden != hidden) {
		self.binNameHidden = hidden;	/// for these labels, the bandlayer is not hosted by the layer, so we must hide/show it separately
		super.hidden = hidden;
	}
}


- (void)setBinNameHidden:(BOOL)binNameHidden {
	if(!self.hidden) {
		_binNameHidden = binNameHidden;
		if(!binNameHidden) {
			bandLayer.hidden = NO;
		} else if(!_hovered && !_highlighted) {
			bandLayer.hidden = YES;
		}
	}
}


- (BOOL)binNameHidden {
	return bandLayer.isHidden;
}


-(NSRect)binNameRect {
	return bandLayer.frame;
}


- (void)reposition {
	TraceView *view = self.view;
	CGFloat hScale = view.hScale;
	if(hScale <= 0) {
		return;
	}

	float startSize = self.startSize;
	float endSize = self.endSize;
	CGFloat startX = [view xForSize:startSize];
	regionRect = NSMakeRect(startX, 0, (endSize - startSize) * hScale, NSMaxY(view.bounds));
	
	self.frame = regionRect;
	
	/// The layer is a bit taller than its host view to hide the bottom and top edges.
	layer.frame = CGRectInset(regionRect, 0, -2);
	
	[self layoutInternalLayers];
	
	/// if we show a popover, we move it in sync with the label (the markerView doesn't scroll).
	if(self.attachedPopover) {
		self.attachedPopover.positioningRect = regionRect;
	}
}


- (BOOL)allowsAnimations {
	return _allowsAnimations && _parentLabel.allowsAnimations;
}


- (void)_shiftByOffset:(MarkerOffset)offset {
	Bin *bin = self.region;
	float midBinLabelPos = (bin.end + bin.start)/2 * offset.slope + offset.intercept;
	float halfBinWidth = (bin.end - bin.start)/2;
	_start = midBinLabelPos - halfBinWidth;
	_end = midBinLabelPos + halfBinWidth;
}


- (void)layoutInternalLayers {
	CGRect rect = stringLayer.bounds;
	if(rect.size.width < regionRect.size.width) {
		rect.size.width = regionRect.size.width;
	}
	bandLayer.bounds = rect;
	bandLayer.position = CGPointMake(NSMidX(regionRect), NSMaxY(regionRect));
	stringLayer.position = CGPointMake(NSMidX(rect), NSMidY(rect));
}


+ (void)arrangeLabels:(NSArray *)binLabels withRepositioning:(BOOL)reposition {
	CGFloat currentMaxX = 0;
	for(BinLabel *binLabel in binLabels) {
		if(!binLabel.hidden) {
			if(reposition) {
				[binLabel reposition];
			}
			CALayer *bandLayer = binLabel->bandLayer;
			NSRect nameRect = bandLayer.frame;
			CGFloat nameRectMinX = nameRect.origin.x;
			BOOL hideBinName = nameRectMinX <= currentMaxX;
			binLabel.binNameHidden = hideBinName;
			if(!bandLayer.hidden) {
				CGFloat nameRectMaxX = NSMaxX(nameRect);
				if(nameRectMaxX > currentMaxX) {
					currentMaxX = nameRectMaxX;
				}
				if(hideBinName) {
					/// Here, the overlaps with a previous one, which is normal if the label is hovered or highlighted
					/// We go back to hide names of previous bins that overlap.
					CGFloat nameRectMinX = nameRect.origin.x;
					for(BinLabel *previousBinLabel in binLabels) {
						if(previousBinLabel != binLabel) {
							if(!previousBinLabel.binNameHidden && NSMaxX(previousBinLabel->bandLayer.frame) >= nameRectMinX) {
								previousBinLabel.binNameHidden = YES;
							}
						} else {
							break;
						}
					}
				}
			}
		}
	}
}


-(void)setFrame:(NSRect)frame {
	_frame = frame;
}


- (nullable NSMenu *)menu {
	_menu = super.menu;
	if(_menu.itemArray.count < 2) {
		/// we just add a menu item allowing to delete our bin
		[_menu addItemWithTitle:@"Delete" action:@selector(deleteAction:) keyEquivalent:@""];
		[_menu.itemArray.lastObject setOffStateImage:[NSImage imageNamed:ACImageNameTrash]];
		for(NSMenuItem *item in self.menu.itemArray) {
			item.target = self;
		}
	}
	return _menu;
}


- (void)deleteAction:(id)sender {
	/// This deletes the bin represented by the label.
	if (!_dragged) {
		Region *bin = self.region;
		NSManagedObjectContext *MOC = bin.managedObjectContext;
		if(MOC) {
			[MOC deleteObject:bin];
			[self.view.undoManager setActionName: self.deleteActionTitle];
		}
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
