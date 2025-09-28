//
//  FittingView.m
//  STRyper
//
//  Created by Jean Peccoud on 04/10/2022.
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



#import "FittingView.h"
#import "LadderFragment.h"
#import "SizeStandard.h"
#import "GeneratedAssetSymbols.h"

@interface FittingView()

/// The ladder trace of the sample.
@property (nullable, nonatomic, weak) Trace* trace;
@property (nonatomic) BOOL needsUpdateDisplay;


@end


@implementation FittingView {
	NSBezierPath *curve;		/// the path used to draw the curve
	NSColor *traceColor;		/// the curve is drawn using this color
	CGFloat vScale;				/// number of quartz points per base pair (y axis)
	NSAttributedString *string; /// The test to show when the fitting curve cannot be drawn.
	NSUInteger sampleCount;		/// Number of loaded samples
	
	/// We show a horizontal dashed line to indicate the size in base pairs corresponding to the current mouse location
	CAShapeLayer *dashedLineLayer;
	CATextLayer *sizeLayer;		/// this show the size at the mouse location
	int firstScan;				/// the scan at x = 0 in the view bounds
	int lastScan;				/// the scan at the max x in the view bounds
	BOOL changedAppearance;		/// true when the colors of the dashedLineLayer needs to be set (to react to change in theme, in particular)
	CGFloat lowestSubviewPosition;	/// used to avoid showing the dashLineLayer behind our subviews
	CGFloat maxXSubviewPosition;	/// used to avoid showing the dashLineLayer behind our subviews
}

# pragma mark - init and attribute setting

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		[self setAttributes];
	}
	return self;
}


- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if (self) {
		[self setAttributes];
	}
	return self;
}


- (void)setAttributes {
	if(!dashedLineLayer) {
		self.wantsLayer = YES;
		curve = NSBezierPath.new;
		curve.lineWidth = 1.0;
		
		
		/// initializing the horizontal dashed line layer ands its text layer
		dashedLineLayer = CAShapeLayer.new;
		dashedLineLayer.anchorPoint = CGPointMake(1, 0.5);
		dashedLineLayer.strokeColor = NSColor.grayColor.CGColor;
		dashedLineLayer.lineWidth = 1.0;
		dashedLineLayer.lineDashPattern = @[@(1.0), @(2.0)];
		dashedLineLayer.delegate = self;
		dashedLineLayer.bounds = CGRectMake(0, 0, self.bounds.size.width, 1);
		
		sizeLayer = CATextLayer.new;
		sizeLayer.font = (__bridge CFTypeRef _Nullable)([NSFont labelFontOfSize:10.0]);
		sizeLayer.fontSize = 10.0;
		sizeLayer.contentsScale = 3.0;
		sizeLayer.bounds = CGRectMake(0, 0, 45, 12);
		sizeLayer.anchorPoint = CGPointMake(1, 0);
		sizeLayer.delegate = self;
		[dashedLineLayer addSublayer:sizeLayer];
		[self.layer addSublayer:dashedLineLayer];
		
		[self updateDashedLine];
		
		changedAppearance = YES;
		
		/// we need a tracking area to track mouse movement, as we show the size corresponding to the mouse location on the Y axis
		NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:self.visibleRect
																	options: NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
																	  owner:self userInfo:nil];
		[self addTrackingArea:trackingArea];
		traceColor = NSColor.orangeColor;
	}
	_noSampleString = @"No sample selected";
	_multipleSampleString = @"Multiple samples selected";
	_noSizingString = @"No size standard applied";
	_failedSizingString = @"Sample sizing failed";
}


- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
	if(layer == sizeLayer || layer == dashedLineLayer) {
		return NSNull.null;
	}
	return nil;
}


- (BOOL)isOpaque {
	return NO;
}


# pragma mark - dashed line

- (void)setFrameSize:(NSSize)newSize {
	[super setFrameSize:newSize];
	[self updateLimits];
	[self updateDashedLine];

}

/// update the geometry of the dashed line
-(void) updateDashedLine {
	if(!dashedLineLayer) {
		return;
	}
	dashedLineLayer.bounds = CGRectMake(0, 0, self.bounds.size.width, 1);
	CGMutablePathRef path = CGPathCreateMutable();
	CGPathMoveToPoint(path, NULL, 0, 0.5);
	CGPathAddLineToPoint(path, NULL, NSMaxX(self.bounds), 0.5);
	dashedLineLayer.path = path;
	CGPathRelease(path);
	sizeLayer.position = CGPointMake(NSMaxX(dashedLineLayer.bounds)-2, 2);

}


-(void)updateLimits {
	lowestSubviewPosition = INFINITY;
	maxXSubviewPosition = 0;
	CGFloat superviewHeight = NSMaxY(self.superview.bounds);
	for(NSView *view in self.superview.subviews) {
		if([view isKindOfClass:NSPopUpButton.class]) {
			CGFloat y = superviewHeight - NSMaxY(view.frame);
			if(y < lowestSubviewPosition) {
				lowestSubviewPosition = y;
			}
			CGFloat x = NSMaxX(view.frame);
			if(x > maxXSubviewPosition) {
				maxXSubviewPosition = x;
			}
		}
	}
	NSPoint position = [self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
	[self showPosition:position];
	
}

# pragma mark - setting content

- (void)setSamples:(NSArray<Chromatogram *> *)samples {
	sampleCount = samples.count;
	if(sampleCount == 1) {
		/// we show the curve only if one sample is selected
		Chromatogram *sample = samples.firstObject;
		self.trace = sample.ladderTrace;
		traceColor = self.trace.channel == redChannelNumber ? [NSColor colorNamed:ACColorNameRedChannelColor] : [NSColor colorNamed:ACColorNameOrangeChannelColor];
	} else {
		self.trace = nil;
	}
}


- (void)setTrace:(Trace *)aTrace {
	if(_trace.chromatogram) {
		[_trace.chromatogram removeObserver:self forKeyPath:ChromatogramCoefsKey];
	}
	_trace = aTrace;
	Chromatogram *sample = _trace.chromatogram;
	if(sample) {
		/// we observe changes in the sizing of the sample, to redraw the curve if needed
		[sample addObserver:self forKeyPath:ChromatogramCoefsKey options:NSKeyValueObservingOptionNew context:nil];
	}
	self.needsUpdateDisplay = YES;
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if([keyPath isEqualToString:ChromatogramCoefsKey]) {
		/// we update the view at the next cycle because several properties of the trace and sample changes successively (sizing quality, ladder fragments...). We wait until all is done.
		self.needsUpdateDisplay = YES;
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}


- (void)setNeedsUpdateDisplay:(BOOL)needsUpdateDisplay {
	_needsUpdateDisplay = needsUpdateDisplay;
	if(needsUpdateDisplay) {
		self.needsDisplay = YES;
	}
}


-(void) updateDisplay {
	Chromatogram *sample = self.trace.chromatogram;
	/// if there sample is not sized, we hide certain elements
	string = nil;
	if(sample == nil || sample.sizingQuality == nil) {
		NSString *stringToShow;
		dashedLineLayer.hidden = YES;
		if(sampleCount > 1) {
			stringToShow = self.multipleSampleString;
		} else if(!sample) {
			stringToShow = self.noSampleString;
		} else {
			stringToShow = sample.sizeStandard == nil? self.noSizingString : self.failedSizingString;
		}
		NSDictionary *attributes = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:13], NSForegroundColorAttributeName:NSColor.labelColor};
		string = [[NSAttributedString alloc] initWithString:stringToShow attributes:attributes];
	} else {
		/// we scale the plot such that the line corresponding to a linear regression between scan and size is the diagonal of the view (ascending from left to right)
		/// The first scan is the one corresponding to size 0 according to this regression
		float minSize = INFINITY;
		float maxSize = 0;
		int nFragments = 0; /// number of fragments assigned to sizes
		for(LadderFragment *fragment in self.trace.fragments) {
			if(fragment.scan > 0) { /// fragments with scan 0 are not assigned
				nFragments++;
				float size = fragment.size;
				minSize = MIN(size, minSize);
				maxSize = MAX(size, maxSize);
			}
		}
		
		if(nFragments > 3) {
			float margin = (maxSize - minSize)/ 20;
			minSize = MIN(0, minSize-margin);
			maxSize = MAX(sample.nScans * sample.sizingSlope + sample.intercept, maxSize+margin);
			firstScan = (minSize - sample.intercept)/sample.sizingSlope;
			lastScan = (maxSize - sample.intercept)/sample.sizingSlope;
		} else {
			firstScan = 0;
			lastScan = sample.nScans;
		}
		/// we update the coordinates used to draw the dash line layer in the next cycle as some subviews are not yet updated to new sample data
		[self performSelector:@selector(updateLimits) withObject:nil afterDelay:0.0];
	}
}



# pragma mark - drawing

- (void)viewDidChangeEffectiveAppearance {
	changedAppearance = YES;
	[super viewDidChangeEffectiveAppearance];
}


- (void)drawRect:(NSRect)dirtyRect {
	if(_needsUpdateDisplay) {
		[self updateDisplay];
	}
		
	NSRect bounds = self.bounds;
	if(string) {
		NSSize stringSize = string.size;
		NSPoint point = NSMakePoint(NSMidX(bounds)-stringSize.width/2, 0);
		point.y = MIN(lowestSubviewPosition-15, NSMidY(bounds)) - stringSize.height/2;
		[string drawAtPoint:point];
		return;
	}
	
	/// to adapt to the app theme, the background color of this layer must be set during drawRect:
	if(changedAppearance) {
		sizeLayer.backgroundColor = [[NSColor colorNamed:ACColorNameViewBackgroundColor] colorWithAlphaComponent:0.7].CGColor;
		sizeLayer.foregroundColor = NSColor.labelColor.CGColor;
		changedAppearance = NO;
	}

	Chromatogram *sample = self.trace.chromatogram;
	if(!sample) {
		return;
	}
	
	CGFloat width = bounds.size.width;
	CGFloat height = bounds.size.height;

	/// we won't add a point to the curve for every scan. We add approximately one point every two quartz points
	/// The increment is the number of scans from one point to the next
	int increment = (int)((lastScan-firstScan)/width *2);
	if (increment < 1) {
		increment = 1;
	}
		
	/// the vertical scale is our height divided by the size at the last scan
	vScale = height / (lastScan*sample.sizingSlope + sample.intercept);
	CGFloat hScale = width / (lastScan - firstScan);
	
	/// if the fitting method is not the linear regression, we draw a line corresponding to the linear regression, for comparison
	if(sample.polynomialOrder > 0) {
		/// as we draw the curve in a different color, we draw a legend indicating which curve is which
		[NSColor.secondaryLabelColor setStroke];
		[NSBezierPath strokeLineFromPoint:NSMakePoint(0, 0) toPoint:NSMakePoint(width, height)];
	}
	/// We now draw the curve corresponding to the current fitting method
	const int maxPointsInCurve = 40;
	/// We stoke the curve if it has enough points. Numbers between 10-100 seem to yield the best performance
	NSPoint pointArray[maxPointsInCurve];          		/// points to add to the curve
	int pointsInPath = 0;
	
	[traceColor setStroke];
	int startScan = MAX(firstScan, 0);
	int nScans = sample.nScans;
	for(int scan = startScan; scan < nScans; scan += increment) {
		CGPoint point = CGPointMake((scan - firstScan) * hScale, [sample sizeForScan:scan] *vScale);
		pointArray[pointsInPath] = point;
		pointsInPath++;

		if(pointsInPath == maxPointsInCurve || scan + increment >= nScans) {
			[curve appendBezierPathWithPoints:pointArray count:pointsInPath];
			[curve stroke];
			[curve removeAllPoints];
			/// The first point in the next path is the last of the previous path. If we don't do that, there is a gap between paths.
			pointArray[0] = pointArray[pointsInPath-1];
			pointsInPath = 1;
		}
	}
	
	/// We indicate the positions of ladder fragments with crosses
	[NSColor.labelColor setFill];
	for(LadderFragment *fragment in self.trace.fragments) {
		if(fragment.scan <= 0) continue;
		NSPoint point = NSMakePoint((fragment.scan - firstScan) *hScale , fragment.size *vScale);
		NSRect horizontalLine = NSMakeRect(point.x - 5, point.y - 0.5, 10, 1);
		NSRect verticalLine = NSMakeRect(point.x - 0.5, point.y - 5, 1, 10);
		NSRectFill(horizontalLine);
		NSRectFill(verticalLine);
	}
}

# pragma mark - responding to user actions

- (void)mouseExited:(NSEvent *)event {
	dashedLineLayer.hidden = YES;
}


- (void)mouseEntered:(NSEvent *)event {
	[NSCursor.arrowCursor set];
	if(self.trace && !string) {
		dashedLineLayer.hidden = NO;
	}
}


- (void)mouseMoved:(NSEvent *)event {
	if(!string) {
		[self showPosition: [self convertPoint:event.locationInWindow fromView:nil]];
	}
}


-(void)showPosition:(NSPoint)mouseLocation {
	if(!dashedLineLayer.isHidden) {
		CGFloat currentSize = mouseLocation.y / vScale;
		sizeLayer.string = [[NSString stringWithFormat:@"%.01f", currentSize] stringByAppendingString:@" bp"];
		dashedLineLayer.position = CGPointMake(NSMaxX(self.bounds), mouseLocation.y);
		dashedLineLayer.strokeStart = mouseLocation.y < lowestSubviewPosition? 0.0: maxXSubviewPosition/self.bounds.size.width;
	}
}

# pragma mark - other

- (void)dealloc {
	self.trace = nil;	/// which removes ourselves as observer
}

@end
