//
//  TracePreviewView.m
//  QLPreviewABIF
//
//  Created by Jean Peccoud on 04/11/2023.
//
//  Created by Jean Peccoud on 28/03/2022.
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



#import "TracePreviewView.h"
#include <sys/sysctl.h>

@interface TracePreviewView ()

@property (nonatomic) float hScale;

@end



@implementation TracePreviewView {
	short maxFluo;
	float vScale;
	long totScans;
	BOOL hasBeenZoomed;
	BOOL dontScroll;
}


static BOOL appleSilicon;

static NSArray <NSColor *> *colorsForChannel;
static NSColor *backgroundColor;

+ (void)initialize {
	if (self == [TracePreviewView class]) {
		size_t size = 100;		/// To make sure that we can read the whole CPU name.
		char string[size];
		sysctlbyname("machdep.cpu.brand_string", &string, &size, nil, 0);
		appleSilicon = strncmp(string, "Apple", 5) == 0;
		colorsForChannel = @[[NSColor colorNamed:@"BlueChannelColor"], [NSColor colorNamed:@"GreenChannelColor"], [NSColor colorNamed:@"BlackChannelColor"], [NSColor colorNamed:@"RedChannelColor"], [NSColor colorNamed:@"OrangeChannelColor"]];
		backgroundColor = [NSColor colorNamed:@"traceViewBackgroundColor"];
	}
}


- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if(self) {
		[self setAttributes];
	}
	return self;
}


- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if(self) {
		[self setAttributes];
	}
	return self;
}


-(void)setAttributes {
	[self setBoundsOrigin:NSMakePoint(0, -1)];
	self.wantsLayer = YES;
	self.layer.drawsAsynchronously = YES;
}


- (BOOL)clipsToBounds {
	return !dontScroll;
}


- (NSInteger)tag {
	return 99;
}


- (void)drawRect:(NSRect)dirtyRect {
	
	if(totScans <= 0) {
		return;
	}
		
	[backgroundColor setFill];
	NSRectFill(dirtyRect);
	
	if(maxFluo > 0) {
		vScale = (NSMaxY(self.bounds) - 20)/ maxFluo;
	} else {
		vScale = 0.1;
	}
	
	float hScale = self.hScale;
	if(hScale <= 0) {
		return;
	}
	
	NSGraphicsContext *currentContext = NSGraphicsContext.currentContext;
	if(!currentContext) {
		return;
	}
	
	CGContextRef ctx = currentContext.CGContext;
	
	short lowerFluo = 1 / vScale; 	/// to quickly evaluate if some scans should be drawn

	int maxPointsInCurve = appleSilicon? 40 : 400;			/// we stoke the curve if it has enough points.
	NSPoint pointArray[maxPointsInCurve];          			/// points to add to the curve
	int startScan = dirtyRect.origin.x / hScale -3;			/// The 3-scan margin is necessary to avoid drawing artifacts.
	if(startScan < 0) {
		startScan = 0;
	}
	
	int endScan = NSMaxX(dirtyRect) / hScale +3;
	
	
	int color = -1;
	for (NSData *fluoData in self.traces) {
		color++;
		if(color > 4) {
			return;
		}

		const int16_t *fluo = fluoData.bytes;
		long nRecordedScans = fluoData.length/sizeof(int16_t);
		int maxScan = nRecordedScans < endScan ? (int)nRecordedScans : endScan;
		
		NSColor *curveColor = colorsForChannel[color];
		CGContextSetStrokeColorWithColor(ctx, curveColor.CGColor);
		float lastX = startScan * hScale;
		float y = fluo[startScan]*vScale;
		if (y < 1) {
			y = 0;
		}
		pointArray[0] = CGPointMake(lastX, y);
		int pointsInPath = 1;		/// current number of points being added
				
		for(int scan = startScan+1; scan <= maxScan; scan++) {
			
			float x = scan * hScale;
			
			int16_t scanFluo = fluo[scan];
			if (scan < maxScan-1) {
				/// we may skip a point that is too close from previously drawn scans and not a local minimum / maximum
				/// or that is lower than the fluo threshold
				int16_t previousFluo = fluo[scan-1];
				int16_t nextFluo = fluo[scan+1];
				if((x-lastX < 1 && !(previousFluo >= scanFluo && nextFluo > scanFluo) &&
					!(previousFluo <= scanFluo && nextFluo < scanFluo)) || scanFluo < lowerFluo) {
					/// and that is not the first/last of a series of scans under the lower threshold
					if(!(scanFluo <= lowerFluo && (previousFluo > lowerFluo || nextFluo > lowerFluo))) {
						continue;
					}
				}
			}
			lastX = x;
			float y = scanFluo * vScale;
			if (y < 1) {
				y = 0;
			}
			
			CGPoint point = CGPointMake(x, y);
			pointArray[pointsInPath++] = point;
			if(pointsInPath == maxPointsInCurve || scan == maxScan -1) {
				if(appleSilicon) {
					/// On Apple Silicon Macs, stroking a path is faster (the GPU is used)
					CGContextBeginPath(ctx);
					CGContextAddLines(ctx, pointArray, pointsInPath);
					CGContextStrokePath(ctx);
				} else {
					/// On intel Macs (which cannot use the GPU for drawing), stroking line segments is faster.
					CGContextStrokeLineSegments(ctx, pointArray, pointsInPath);
				}
				pointArray[0] = point;
				pointsInPath = 1;
			} else if(!appleSilicon) {
				/// On intel, we draw unconnected depend line segments, so the end of each segment is the start of the next one
				pointArray[pointsInPath++] = point;
			}
		}
	}
}



- (BOOL)isOpaque {
	return NO;
}


- (BOOL)preservesContentDuringLiveResize {
	return YES;
}


- (void)setHScale:(float)hScale {
	if(hScale < 0.05) {
		hScale = 0.05;
	}
	
	NSSize boundSize = self.superview.bounds.size;
	float superviewWidth = boundSize.width;
	float minScale = superviewWidth / totScans;
	if(hScale < minScale) {
		hScale = minScale;
	} else if(hScale > 2) {
		hScale = 2;
	}
	
	if(hScale != _hScale) {
		_hScale = hScale;
		NSSize currentSize = self.frame.size;
		float newWidth = totScans * hScale;
		if(newWidth < superviewWidth) {
			newWidth = superviewWidth;
		}
		currentSize.width = newWidth;
		currentSize.height = boundSize.height;
		dontScroll = YES;
		[self setFrameSize:currentSize];
		dontScroll = NO;
	}
}


- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
	float width = self.superview.bounds.size.width;
	if(width > self.frame.size.width || !hasBeenZoomed) {
		self.hScale = width / totScans;
	}
}




- (void)setTraces:(NSArray<NSData *> *)traces {
	_traces = traces;
	maxFluo = 0;
	totScans = 0;
	for(NSData *traceData in traces) {
		const int16_t *fluo = traceData.bytes;
		long nScans = traceData.length / sizeof(int16_t);
		if(nScans > totScans) {
			totScans = nScans;
		}
		for (int scan = 0; scan < nScans; scan++) {
			if(fluo[scan] > maxFluo) {
				maxFluo = fluo[scan];
			}
		}
	}

	hasBeenZoomed = NO;
	self.hScale = self.superview.bounds.size.width / totScans;
	self.needsDisplay = YES;
}



- (void)magnifyWithEvent:(NSEvent *)theEvent    {
	float zoomFactor = 1+theEvent.magnification;
	NSPoint location = [self convertPoint:theEvent.locationInWindow fromView:nil];
	[self zoomTo:location.x withFactor:zoomFactor];
	
}



- (void)scrollWheel:(NSEvent *)theEvent {
	
	float deltaX = theEvent.scrollingDeltaX;
	BOOL vertical = fabs(deltaX) < fabs(theEvent.scrollingDeltaY);
	BOOL altKeyDown = (theEvent.modifierFlags & NSEventModifierFlagOption) != 0;
	if (altKeyDown && vertical) {
		/// if scrolling is mostly vertical and the alt key is pressed, we zoom the trace
		NSPoint mouseLocation = [self convertPoint:theEvent.locationInWindow fromView:nil];
		float zoomFactor = (40 + theEvent.scrollingDeltaY)/40;
		[self zoomTo:mouseLocation.x withFactor:zoomFactor];
	}
	else [super scrollWheel:theEvent];
}


- (void)zoomTo:(float) zoomPoint withFactor:(float)zoomFactor {
	
	if (zoomFactor <= 0) {
		zoomFactor = 0.01;
	}
	
	float newScale = self.hScale * zoomFactor;
	float ratio = zoomPoint / self.frame.size.width;;
	float distanceFromLeft = zoomPoint - self.visibleRect.origin.x;

	self.hScale = newScale;
	
	float newVisibleOrigin = ratio * self.frame.size.width - distanceFromLeft;
	if(newVisibleOrigin < 0) {
		newVisibleOrigin = 0;
	}
	
	NSClipView *clipView = (NSClipView *)self.superview;
	if (clipView.bounds.origin.x != newVisibleOrigin) {
		[clipView scrollToPoint:NSMakePoint(newVisibleOrigin, 0)];
		[self.enclosingScrollView reflectScrolledClipView:clipView];
	}
	hasBeenZoomed = YES;
}


@end
