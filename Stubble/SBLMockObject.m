#import "SBLMockObject.h"
#import "SBLTransactionManager.h"
#import "SBLErrors.h"
#import "SBLTimesMatcher.h"
#import "SBLProtocolMockObjectBehavior.h"
#import "SBLClassMockObjectBehavior.h"

@interface SBLMockObject ()

@property (nonatomic, readonly) id<SBLMockObjectBehavior> sblBehavior;
@property (nonatomic, readonly) NSMutableArray *sblStubbedInvocations;
@property (nonatomic, readonly) NSMutableArray *sblActualInvocationsArray;
@property (nonatomic, readwrite) SBLInvocationRecord *sblVerifyInvocation;
@property (nonatomic, readwrite) NSUInteger *sblNumberOfInvocations;

@end

@implementation SBLMockObject

+ (id)sblMockForClass:(Class)class {
    return [[SBLMockObject alloc] initWithBehavior:[[SBLClassMockObjectBehavior alloc] initWithClass:class]];
}

+ (id)sblMockForProtocol:(Protocol *)protocol {
    return [[SBLMockObject alloc] initWithBehavior:[[SBLProtocolMockObjectBehavior alloc] initWithProtocol:protocol]];
}

- (instancetype)initWithBehavior:(id<SBLMockObjectBehavior>)behavior {
    _sblBehavior = behavior;
	_sblStubbedInvocations = [NSMutableArray array];
    _sblActualInvocationsArray = [NSMutableArray array];
    _sblNumberOfInvocations = 0;
	return self;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
	return [self.sblBehavior mockObjectMethodSignatureForSelector:aSelector];
}

- (BOOL)respondsToSelector:(SEL)selector {
	return [self.sblBehavior mockObjectRespondsToSelector:selector];
}

- (BOOL)isKindOfClass:(Class)aClass {
	return [self.sblBehavior mockObjectIsKindOfClass:aClass];
}

- (BOOL)conformsToProtocol:(Protocol *)aProtocol {
	return [self.sblBehavior mockObjectConformsToProtocol:aProtocol];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    self.sblNumberOfInvocations++;

	if (SBLTransactionManager.currentTransactionManager.state == SBLTransactionManagerStateStubInProgress) {
		[self.sblStubbedInvocations addObject:[[SBLStubbedInvocation alloc] initWithInvocation:invocation]];
		[SBLTransactionManager.currentTransactionManager whenMethodInvokedForMock:self];
	} else if (SBLTransactionManager.currentTransactionManager.state == SBLTransactionManagerStateVerifyInProgress) {
        self.sblVerifyInvocation = [[SBLInvocationRecord alloc] initWithInvocation:invocation];
        [SBLTransactionManager.currentTransactionManager verifyMethodInvokedForMock:self];
    } else {
		// Find Matching Stub
		SBLStubbedInvocation *matchingWhen = nil;
		for (SBLStubbedInvocation *ongoingWhen in self.sblStubbedInvocations.reverseObjectEnumerator) {
			if ([ongoingWhen matchesInvocation:invocation]) {
				matchingWhen = ongoingWhen;
				break;
			}
		}
		
		// Perform Actions
		for (SBLInvocationActionBlock action in matchingWhen.actionBlocks) {
			action(invocation);
		}
		
		// Invoke and Record Invocation
		[invocation invokeWithTarget:nil];
        [invocation retainArguments];
        [self.sblActualInvocationsArray addObject:invocation];
	}
}

- (NSArray *)sblActualInvocations {
    return self.sblActualInvocationsArray;
}

- (SBLVerificationResult *)sblVerifyMockNotCalled {
    if ([self sblNumberOfInvocations]) {
        return [[SBLVerificationResult alloc] initWithSuccess:NO failureDescription:SBLMethodWasCalledUnexpectedly];
    }
    return [[SBLVerificationResult alloc] initWithSuccess:YES failureDescription:nil];
}

- (SBLStubbedInvocation *)sblCurrentStubbedInvocation {
	return [self.sblStubbedInvocations lastObject];
}

- (SBLVerificationResult *)sblVerifyInvocationOccurredNumberOfTimes:(SBLTimesMatcher *)timesMatcher {
	[self sblValidateTimesMatcherUsage:timesMatcher];

    NSInteger atLeastTimes = timesMatcher.atLeast;
    NSInteger atMostTimes = timesMatcher.atMost;
    NSInteger invocationCount = 0;
    for (NSInvocation *actualInvocation in self.sblActualInvocations) {
        if ([self.sblVerifyInvocation matchesInvocation:actualInvocation]) {
            invocationCount++;
        }
    }
	
	BOOL success = atLeastTimes <= invocationCount && invocationCount <= atMostTimes;
	NSString *failureMessage = nil;
    if (!success) {
        NSString *countString = invocationCount == 1 ? @"1 time" : [NSString stringWithFormat:@"%ld times", (long)invocationCount];
        NSString *actualString = [NSString stringWithFormat:@"Method '%@' was called %@ ", NSStringFromSelector(self.sblVerifyInvocation.selector), countString];
        NSString *expectedString;
        if (atMostTimes == 0) {
            expectedString = @"(expected no calls)";
        } else if (atMostTimes == NSIntegerMax) {
            expectedString = [NSString stringWithFormat:@"(expected at least %ld)", (long)atLeastTimes];
        } else if (atMostTimes == atLeastTimes) {
            expectedString = [NSString stringWithFormat:@"(expected exactly %ld)", (long)atLeastTimes];
        } else {
            expectedString = [NSString stringWithFormat:@"(expected between %ld and %ld)", (long)atLeastTimes, (long)atMostTimes];
        }
        failureMessage = [actualString stringByAppendingString:expectedString];
    }
	return [[SBLVerificationResult alloc] initWithSuccess:success failureDescription:failureMessage];
}

- (void)sblValidateTimesMatcherUsage:(SBLTimesMatcher *)timesMatcher {
    if (timesMatcher.atMost == NSIntegerMax && timesMatcher.atLeast < 1) {
        [NSException raise:SBLBadUsage format:SBLBadAtLeastTimesProvided];
    } else if (timesMatcher.atLeast < 0 || timesMatcher.atMost < 0) {
        [NSException raise:SBLBadUsage format:SBLBadTimesProvided];
    } else if (timesMatcher.atLeast > timesMatcher.atMost || timesMatcher.atMost < timesMatcher.atLeast) {
        [NSException raise:SBLBadUsage format:SBLAtLeastCannotBeGreaterThanAtMost];
    } else if (timesMatcher.atMost == INT_MAX && timesMatcher.atLeast < 1) {
        [NSException raise:SBLBadUsage format:SBLBadAtLeastTimesProvided];
    }
}

@end