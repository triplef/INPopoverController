//
//  PopoverSampleAppAppDelegate.m
//  Copyright 2011 Indragie Karunaratne. All rights reserved.
//
//  Licensed under the BSD License <http://www.opensource.org/licenses/bsd-license>
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import "PopoverSampleAppAppDelegate.h"
#import "ContentViewController.h"
#import "INPopoverController.h"

@implementation PopoverSampleAppAppDelegate

@synthesize window, popoverController;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    ContentViewController *viewController = [[[ContentViewController alloc] initWithNibName:@"ContentViewController" bundle:nil] autorelease];
    self.popoverController = [[[INPopoverController alloc] initWithContentViewController:viewController] autorelease];
    self.popoverController.closesWhenPopoverResignsKey = NO;
    self.popoverController.color = [NSColor colorWithCalibratedWhite:1.0 alpha:0.8];
    self.popoverController.borderColor = [NSColor blackColor];
    self.popoverController.borderWidth = 2.0;
}

- (IBAction)togglePopover:(id)sender
{
    if (self.popoverController.popoverIsVisible) {
        [self.popoverController closePopover:nil];
    } else {
        NSRect buttonBounds = [sender bounds];
        [self.popoverController showPopoverAtPoint:NSMakePoint(NSMidX(buttonBounds), NSMidY(buttonBounds)) inView:sender preferredArrowDirection:INPopoverArrowDirectionLeft anchorsToPositionView:YES];
    }
}

- (void)dealloc
{
    [popoverController release];
    [super dealloc];
}
@end