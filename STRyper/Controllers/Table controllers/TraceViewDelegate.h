//
//  TraceViewDelegate.h
//  STRyper
//
//  Created by Jean Peccoud on 20/01/2023.
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



#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A set of methods that a ``TraceView`` expects from its delegate.
@protocol TraceViewDelegate <NSObject>


/// Returns the appropriate visible range the traceView should use to show its content (see ``TraceView/visibleRange``);
- (BaseRange)visibleRangeForTraceView:(TraceView *)traceView;

/// Returns the appropriate top fluorescence level that the traceView should use to show its content (see ``TraceView/topFluoLevel``);
- (float)topFluoLevelForTraceView:(TraceView *)traceView;

@optional

/// Message sent by a traceView when its visibleRange is modified by methods that trigger a notification. (see TraceView.h)
/// The delegate can use these to synchronize the horizontal positions and scales, as well as the vertical scale of curves, between views
/// these methods are not called if the view has its visibleRange and topFluoLevel changed by a method that does not notify (for instance -setVisibleRange:).
/// If they were, synchronizing between views would be difficult, if not impossible, as the views that are moved in response to these messages would themselves send this message.
- (void)traceViewDidChangeRangeVisibleRange:(TraceView *)traceView;
- (void)traceViewDidChangeTopFluoLevel:(TraceView *)traceView;

/// Message sent by a traceView when it starts moving to range with animation.
/// This method isn't required to move other view in sync, as `traceViewDidChangeRangeVisibleRange` is sent at every step of the animation.
/// But if (for instance) other animations should be started, this method can be used.
///
/// The traceView doesn't have its visibleRange set to range when this message is received.
- (void)traceView:(TraceView *)traceView didStartMovingToRange:(BaseRange)range;


- (void)traceView:(TraceView *)traceView didClickTrace:(Trace *)trace;


@end

NS_ASSUME_NONNULL_END
