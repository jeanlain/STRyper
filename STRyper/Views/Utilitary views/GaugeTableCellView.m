//
//  GaugeTableCellView.m
//  STRyper
//
//  Created by Jean Peccoud on 11/11/2022.
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



#import "GaugeTableCellView.h"
@import QuartzCore;

@implementation GaugeTableCellView {
	/// The layer that draws the gauge.
	CALayer *gaugeLayer;
	
	/// the object that the view represents. We use it to determine whether we should animate the change in gauge size.
	__weak id currentRepresentedObject;
}


- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if(self) {
		[self setAttributes];
	}
	return self;
}


- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if(self) {
		[self setAttributes];
	}
	return self;
}


-(void) setAttributes {
	if(!gaugeLayer) {
		self.wantsLayer = YES;
		gaugeLayer = CALayer.new;
		gaugeLayer.anchorPoint = CGPointMake(0, 0);
		gaugeLayer.frame = self.layer.bounds;
		gaugeLayer.cornerRadius = 2.0;
		gaugeLayer.delegate = self;
		_animateGauge = YES;
		[self.layer addSublayer:gaugeLayer];
		_gaugeThickness = 3.5;
		_maxValue = 1.0;
		_maxValueColor = [NSColor colorWithCalibratedRed:0 green:0.7 blue:0 alpha:1];
		_minValueColor = NSColor.redColor;
	}
}


- (void)setGaugeThickness:(float)gaugeThickness {
	_gaugeThickness = gaugeThickness;
	[self setGaugeSize];
}


- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
	[super resizeSubviewsWithOldSize:oldSize];
	BOOL previousValue = _animateGauge;
	_animateGauge = NO;
	[self setGaugeSize];
	_animateGauge = previousValue;
}


-(void)setGaugeSize {
	float fraction = self.value/self.maxValue;
	if(fraction < 0) {
		fraction = 0;
	} else if(fraction > 1) {
		fraction = 1;
	}
	gaugeLayer.bounds = CGRectMake(0, 0, NSMaxX(gaugeLayer.superlayer.bounds) * fraction, self.gaugeThickness);
}


/// Updates the gauge color.
-(void)updateColor {
	float fraction = self.value/self.maxValue;
	if(fraction < 0) {
		fraction = 0;
	} else if(fraction > 1) {
		fraction = 1;
	}
	gaugeLayer.backgroundColor = [self.minValueColor blendedColorWithFraction:fraction ofColor:self.maxValueColor].CGColor;
}


- (void)setMinValueColor:(NSColor *)minValueColor {
	_minValueColor = minValueColor;
	[self updateColor];
}


- (void)setMaxValueColor:(NSColor *)maxValueColor {
	_maxValueColor = maxValueColor;
	[self updateColor];
}


- (void)setMaxValue:(float)maxValue {
	if(maxValue >= 0) {
		_maxValue = maxValue;
		self.value = self.value;	/// This updates the gauge.
	}
}


- (void)setValue:(float)gaugeValue {
	
	if(gaugeValue > self.maxValue) {
		gaugeValue = self.maxValue;
	}
	if(gaugeValue < 0) {
		gaugeValue = 0;
	}
	_value = gaugeValue;
	[self updateColor];
	[self setGaugeSize];
	currentRepresentedObject = self.objectValue;
	
}


- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
	/// if the gauge changes because the object value has changed, we don't animate the change
	if(currentRepresentedObject != self.objectValue || !_animateGauge) {
		return NSNull.null;
	}
	return nil;
}

@end
