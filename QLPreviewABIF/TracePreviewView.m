//
//  TracePreviewView.m
//  QLPreviewABIF
//
//  Created by Jean Peccoud on 04/11/2023.
//

#import "TracePreviewView.h"

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


static NSArray *colorsForChannels;
static NSBezierPath *curve;

+ (void)initialize {
	colorsForChannels = @[[NSColor colorWithCalibratedRed:0.1 green:0.1 blue:1 alpha:1],
									 [NSColor colorWithCalibratedRed:0 green:0.7 blue:0 alpha:1],
				   NSColor.darkGrayColor, NSColor.redColor, NSColor.orangeColor];
	curve = NSBezierPath.new;
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
		
	[NSColor.whiteColor setFill];
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
	
	short lowerFluo = 1 / vScale; 	/// to quickly evaluate if some scans should be drawn

	float xFromLastPoint = 0;  				/// the number of quartz points from the last added point, which we use to determine if a scan can be skipped
	float lastX = 0;
	int maxPointsInCurve = 40;					/// we stoke the curve if it has enough points. Numbers between 10-100 seem to yield the best performance
	NSPoint pointArray[maxPointsInCurve];          /// points to add to the curve
	int startScan = dirtyRect.origin.x / hScale -1;
	if(startScan < 0) {
		startScan = 0;
	}
	
	int endScan = NSMaxX(dirtyRect) / hScale +1;
	
	
	int color = -1;
	for (NSData *fluoData in self.traces) {
		color++;
		if(color > 4) {
			return;
		}
		int scanDrawn = 0;

		const int16_t *fluo = fluoData.bytes;
		long nRecordedScans = fluoData.length/sizeof(int16_t);
		int maxScan = nRecordedScans < endScan ? (int)nRecordedScans : endScan;
		
		[colorsForChannels[color] setStroke];
		short pointsInPath = 0;		/// current number of points being added to the path
		for(int scan = startScan; scan <= maxScan; scan++) {
			
			float x = scan * hScale;
			xFromLastPoint = x - lastX;
			
			int16_t scanFluo = fluo[scan];
			if (scan < maxScan-1) {
				/// we may skip a point that is too close from previously drawn scans and not a local minimum / maximum
				/// or that is lower than the fluo threshold
				if((xFromLastPoint < 1 && !(fluo[scan-1] >= scanFluo && fluo[scan+1] > scanFluo) &&
					!(fluo[scan-1] <= scanFluo && fluo[scan+1] < scanFluo)) || scanFluo < lowerFluo) {
					/// and that is not the first/last of a series of scans under the lower threshold
					if(!(scanFluo <= lowerFluo && (fluo[scan-1] > lowerFluo || fluo[scan+1] > lowerFluo))) {
						/// We must draw the first point and the last point outside the dirty rect
						if(scan != startScan) {
							continue;
						}
					}
				}
			}
			lastX = x;
			float y = scanFluo * vScale;
			if (y < 1) {
				y = 0;
			}
			pointArray[pointsInPath++] = CGPointMake(x, y);
			scanDrawn++;
			if (pointsInPath == maxPointsInCurve || scan == maxScan-1) {
				[curve appendBezierPathWithPoints:pointArray count:pointsInPath];
				[curve stroke];
				[curve removeAllPoints];
				pointArray[0] = pointArray[pointsInPath-1];
				/// the first point in the next path is the last of the previous path. If we don't do that, there is a gap between paths.
				pointsInPath = 1;
			}
		}
	}
}



- (BOOL)isOpaque {
	return YES;
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
//	NSLog(@"%s, %f", __PRETTY_FUNCTION__, width);
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
