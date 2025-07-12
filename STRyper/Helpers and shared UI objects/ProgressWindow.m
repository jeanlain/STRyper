//
//  ProgressWindow.m
//  STRyper
//
//  Created by Jean Peccoud on 27/11/2022.
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


#import "ProgressWindow.h"

@interface ProgressWindow ()

@property (nonatomic) NSProgress *progress;

@end


@implementation ProgressWindow  {
	/// outlets backing readonly properties (see corresponding property)
	__weak IBOutlet NSTextField *_operationTextField;
	__weak IBOutlet NSButton *_stopButton;
	__weak IBOutlet NSProgressIndicator *_progressBar;
	
	/// as the window may be asked to show only after a delay, we use these ivars to know how it should show
	/// the window to which the window will be attached
	__weak NSWindow *windowToAttach;
	/// whether the window should be shown as a modal sheet
	BOOL runModal;
	BOOL showProgress;
}

static void *progressChangedContext = &progressChangedContext;



- (instancetype)init {
	self = super.init;
	if(self && [NSBundle.mainBundle loadNibNamed:@"ProgressWindow" owner:self topLevelObjects:nil]) {
		NSView *view = _progressBar.superview;
		if(view) {
			self.contentView = view;
		}
		_closesWhenFinished = YES;
	}
	return self;
}


- (void)showProgressWindowForProgress:(NSProgress *)progress afterDelay:(NSTimeInterval)delay modal:(BOOL)modal parentWindow:(NSWindow *)window {
	self.progress = progress;
	windowToAttach = window;
	runModal = modal;
	showProgress = YES;
	[NSOperationQueue.mainQueue addOperationWithBlock:^{
		[self performSelector:@selector(showProgressWindowIfNeeded) withObject:nil afterDelay:delay];
	}];
}


- (void)setProgress:(NSProgress *)progress {
	static NSArray *observedKeys;			
	if(!observedKeys) {
		observedKeys = @[NSStringFromSelector(@selector(completedUnitCount)),
						 NSStringFromSelector(@selector(localizedDescription)),
						 @"cancellable",		/// there is no selector named "cancellable". Using "isCancellable" does no work.
						 @"cancelled",];		/// ditto
	}
	
	if(_progress) {
		for(NSString *key in observedKeys) {
			[_progress removeObserver:self forKeyPath:key];
		}
	}
	_progress = progress;
	if(progress) {
		for(NSString *key in observedKeys) {
			[progress addObserver:self forKeyPath:key options:NSKeyValueObservingOptionNew context:progressChangedContext];
		}
	}
}


-(void)showProgressWindowIfNeeded {
	if(showProgress) {
		NSProgress *progress = self.progress;
		if(!progress || (progress.fractionCompleted < 0.5 && !progress.isPaused && !progress.isCancelled)) {
			/// the first condition is set to avoid showing the progress window for a amount of time that is too short
			/// (we assume that the delay is a few seconds or less)
			[NSOperationQueue.mainQueue addOperationWithBlock:^{
				[self showProgressWindow];
			}];
		}
	}
}


-(void)showProgressWindow {
	if(!windowToAttach.isVisible) {
		return;
	}
	
	NSProgress *progress = self.progress;
	if(progress.totalUnitCount <= 0) {
		self.progressBar.indeterminate = YES;
		[self.progressBar startAnimation:self];
	} else {
		self.progressBar.indeterminate = NO;
	}
	
	self.stopButton.enabled = progress.isCancellable;
	
	if(!self.isVisible) {
		if(runModal) {
			if(@available(macOS 14, *)) {
				[NSApp activate];
			}
			[windowToAttach beginSheet:self completionHandler:^(NSModalResponse returnCode) {
			}];
		} else {
			/// if the window should not be modal, we center it over the parent window.
			[self makeKeyAndOrderFront:self];
			NSSize size = self.frame.size;
			NSRect frame = windowToAttach.frame;
			NSPoint origin = NSMakePoint(NSMidX(frame), NSMidY(frame));
			origin.x -= size.width/2;
			origin.y -= size.height/2;
			[self setFrameOrigin:origin];
		}
	}
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if (context == progressChangedContext) {
		[NSOperationQueue.mainQueue addOperationWithBlock:^{
			NSProgress *progress = object;
			if(self.isVisible) {
				if([keyPath isEqualToString:@"cancelled"] && progress.isCancelled) {
					[self stopShowingProgressAndClose];
				} else if([keyPath isEqualToString:NSStringFromSelector(@selector(localizedDescription))]) {
					self.operationTextField.stringValue = progress.localizedDescription;
				} else if([keyPath isEqualToString:@"cancellable"]) {
					self.stopButton.enabled = progress.isCancellable;
				} else {
					self.progressBar.doubleValue = progress.fractionCompleted;
					if(progress.isFinished && self.closesWhenFinished && !self.progressBar.isIndeterminate) {
						[self stopShowingProgressAndClose];
					}
				}
			}
		}];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}


- (IBAction)cancelOperation:(id)sender {
	[self.progress cancel];
	[self stopShowingProgressAndClose];
}


- (IBAction)stopShowingProgressAndClose {
	self.progress = nil;
	showProgress = NO;
	[self closeProgressWindow];
}


-(void)closeProgressWindow {
	[NSOperationQueue.mainQueue addOperationWithBlock:^{
		if (self.sheetParent) {
			[self.sheetParent endSheet:self];
		} else if(self.isVisible) {
			[self close];
		}
		[self.progressBar stopAnimation:self];
		self.progressBar.indeterminate = NO;
		self.progressBar.doubleValue = 0.0;
	}];
}

- (void)dealloc {
	self.progress = nil;   	/// this removes us as observers for the progress
}


@end
