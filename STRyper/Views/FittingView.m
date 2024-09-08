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


@interface FittingView()

/// The ladder trace of the sample.
@property (nullable, nonatomic, weak) Trace* trace;

@end


@implementation FittingView {
	NSBezierPath *curve;		/// the path used to draw the curve
	NSColor *traceColor;		/// the curve is drawn using this color
	NSInteger nScans;			/// number of scan in the chromatogram, for quick reference
	float hScale;				/// number of quartz points per scan (x axis)
	float vScale;				/// number of quartz points per base pair (y axis)

	/// We show a horizontal dashed line to indicate the size in base pairs corresponding to the current mouse location
	CAShapeLayer *dashedLineLayer;
	CATextLayer *sizeLayer;		/// this show the size at the mouse location
	float upperLimit;			/// beyond this limit (in points, for the Y dimension of the view), the dashedLineLayer does not draw fully, to avoid overlaps with other elements
	NSInteger firstScan;		/// the scan at x = 0 in the view bounds
	NSInteger lastScan;			/// the scan at the max x in the view bounds
	BOOL changedAppearance;		/// true when the colors of the dashedLineLayer needs to be set (to react to change in theme, in particular)
	BOOL noSizing;				/// true when we cannot show the curve (for various reasons)
	float lowestSubviewPosition;	/// used to avoid showing the dashLineLayer behind our subviews
	float maxXSubviewPosition;	/// used to avoid showing the dashLineLayer behind our subviews
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
		
		_textField = [NSTextField labelWithString:@"No sample selected"];
		_textField.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:_textField];
		[[_textField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor] setActive:YES];
		[[_textField.centerXAnchor constraintEqualToAnchor:self.centerXAnchor] setActive:YES];
		
		
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
		sizeLayer.contentsScale = 2.0;
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
}


- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
	if(layer == sizeLayer || layer == dashedLineLayer) {
		return NSNull.null;
	}
	return nil;
}


- (NSString *)noSampleString {
	if(!_noSampleString) {
		_noSampleString = @"No sample selected";
	}
	return _noSampleString;
}


- (NSString *)multipleSampleString {
	if(!_multipleSampleString) {
		_multipleSampleString = @"Multiple samples selected";
	}
	return _multipleSampleString;
}


- (NSString *)noSizingString {
	if(!_noSizingString) {
		_noSizingString = @"Sample not sized";
	}
	return _noSizingString;
}


- (NSString *)failedSizingString {
	if(!_failedSizingString) {
		_failedSizingString = @"Sample sizing failed";
	}
	return _failedSizingString;
}


- (BOOL)isOpaque {
	return NO;
}


# pragma mark - dashed line

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
	[super resizeSubviewsWithOldSize:oldSize];
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
	float superviewBounds = NSMaxY(self.superview.bounds);
	for(NSView *view in self.superview.subviews) {
		if(view == self) {
			continue;
		}
		float y = superviewBounds - NSMaxY(view.frame);
		if(y < lowestSubviewPosition) {
			lowestSubviewPosition = y;
		}
		float x = NSMaxX(view.frame);
		if(x > maxXSubviewPosition) {
			maxXSubviewPosition = x;
		}
	}
	NSPoint position = [self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
	[self showPosition:position];
	
}

# pragma mark - setting content

- (void)setSamples:(NSArray<Chromatogram *> *)samples {
	if(samples.count == 1) {
		/// we show the curve only if one sample is selected
		Chromatogram *sample = samples.firstObject;
		self.trace = sample.ladderTrace;
		traceColor = self.trace.channel == redChannelNumber ? [NSColor colorNamed:@"RedChannelColor"] : [NSColor colorNamed:@"OrangeChannelColor"];
	} else {
		self.textField.stringValue = samples.count > 1 ? self.multipleSampleString : self.noSampleString;
		self.trace = nil;
	}
}


- (void)setTrace:(Trace *)aTrace {
	if(_trace.chromatogram) {
		[_trace.chromatogram removeObserver:self forKeyPath:ChromatogramSizesKey];
	}
	_trace = aTrace;
	Chromatogram *sample = _trace.chromatogram;
	if(sample) {
		/// we observe changes in the sizing of the sample, to redraw the curve if needed
		[sample addObserver:self forKeyPath:ChromatogramSizesKey options:NSKeyValueObservingOptionNew context:nil];
		nScans = sample.sizes.length / sizeof(float);
	}
	[self updateDisplay];
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if([keyPath isEqualToString:ChromatogramSizesKey]) {
		/// we update the view at the next cycle because several properties of the trace and sample changes successively (sizing quality, ladder fragments...). We wait until all is done.
		[self performSelector:@selector(updateDisplay) withObject:nil afterDelay:0.0];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}


-(void) updateDisplay {
	Chromatogram *sample = self.trace.chromatogram;
	/// if there sample is not sized, we hide certain elements
	noSizing = sample == nil || sample.sizingQuality == nil;
	if(noSizing) {
		dashedLineLayer.hidden = YES;
	}

	if(sample && noSizing) {
		self.textField.stringValue = sample.sizeStandard == nil? self.noSizingString : self.failedSizingString;
	}
	self.textField.hidden = !noSizing;
	
	if(!noSizing) {
		/// we scale the plot such that the line corresponding to a linear regression between scan and size is the diagonal of the view (ascending from left to right)
		/// The first scan is the one corresponding to size 0 according to this regression
		NSSet *fragments = [self.trace.fragments filteredSetUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
			if([evaluatedObject class] == LadderFragment.class) {
				return ((LadderFragment *)evaluatedObject).scan > 0;
			}
			return NO;
		}]];
		
		if(fragments.count > 3) {
			NSArray *sortedFragments = [fragments sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:LadderFragmentSizeKey ascending:YES]]];
			LadderFragment *first = sortedFragments.firstObject;
			float minSize = first.size;
			LadderFragment *last = sortedFragments.lastObject;
			float maxSize = last.size;
			float margin = (maxSize - minSize)/ 20;
			minSize -= margin; maxSize += margin;
			
			if(minSize > 0) {
				minSize = 0;
			}
			float endSize = nScans * sample.sizingSlope + sample.intercept;
			if(maxSize < endSize) {
				maxSize = endSize;
			}
			firstScan = (int)((minSize - sample.intercept)/sample.sizingSlope);
			lastScan = (int)((maxSize - sample.intercept)/sample.sizingSlope);
		} else {
			firstScan = 0;
			lastScan = nScans;
		}
		/// we update the coordinates used to draw the dash line layer in the next cycle as some subviews are not yet updated to new sample data
		[self performSelector:@selector(updateLimits) withObject:nil afterDelay:0.0];
	}

	self.needsDisplay = YES;
}



# pragma mark - drawing

- (void)viewDidChangeEffectiveAppearance {
	changedAppearance = YES;
	[super viewDidChangeEffectiveAppearance];
}


- (void)drawRect:(NSRect)dirtyRect {
	
	if(noSizing) {
		return;
	}
	
	/// to adapt to the app theme, the background color of this layer must be set during drawRect:
	if(changedAppearance) {
		sizeLayer.backgroundColor = [NSColor.windowBackgroundColor colorWithAlphaComponent:0.7].CGColor;
		sizeLayer.foregroundColor = NSColor.labelColor.CGColor;
		changedAppearance = NO;
	}

	Chromatogram *sample = self.trace.chromatogram;
	if(!sample) {
		return;
	}
	
	NSData *sizeData = sample.sizes;
	const float *sizes = sizeData.bytes;
	NSRect bounds = self.bounds;
	float width = bounds.size.width;
	float height = bounds.size.height;

	/// we won't add a point to the curve for every scan. We add approximately one point every two quartz points
	/// The increment is the number of scans from one point to the next
	int increment = (int)((lastScan-firstScan)/width *2);
	if (increment < 1) {
		increment = 1;
	}
		
	/// the vertical scale is our height divided by the size at the last scan
	vScale = height / (lastScan*sample.sizingSlope + sample.intercept);
	hScale = width / (lastScan - firstScan);
	
	/// if the fitting method is not the linear regression, we draw a line corresponding to the linear regression, for comparison
	if(sample.polynomialOrder > 0) {
		/// as we draw the curve in a different color, we draw a legend indicating which curve is which
		[NSColor.secondaryLabelColor setStroke];
		[NSBezierPath strokeLineFromPoint:NSMakePoint(0, 0) toPoint:NSMakePoint(width, height)];
	}
	/// We now draw the curve corresponding to the current fitting method
	int maxPointsInCurve = 40;
	/// We stoke the curve if it has enough points. Numbers between 10-100 seem to yield the best performance
	NSPoint pointArray[maxPointsInCurve];          		/// points to add to the curve
	int pointsInPath = 0;
	
	[traceColor setStroke];
	NSInteger startScan = (firstScan >= 0)? firstScan : 0;

	for(NSInteger scan = startScan; scan < nScans; scan += increment) {
		CGPoint point = CGPointMake((scan - firstScan) * hScale, sizes[scan]*vScale );
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
	if(self.trace && !noSizing) {
		dashedLineLayer.hidden = NO;
	}
}


- (void)mouseMoved:(NSEvent *)event {
	if(noSizing) {
		return;
	}
	[self showPosition: [self convertPoint:event.locationInWindow fromView:nil]];
}


-(void)showPosition:(NSPoint)mouseLocation {
	if(!dashedLineLayer.isHidden) {
		float currentSize = mouseLocation.y / vScale;
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
