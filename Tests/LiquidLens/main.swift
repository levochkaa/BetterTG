// main.swift

import Foundation

run(LiquidLensFlexTests.self, [
    ("testTargetMatchesUIKit", LiquidLensFlexTests.testTargetMatchesUIKit),
    ("testMotionMatchesUIKitIntegrator", LiquidLensFlexTests.testMotionMatchesUIKitIntegrator),
    ("testMovesInOppositeDirectionsAreMirrored", LiquidLensFlexTests.testMovesInOppositeDirectionsAreMirrored),
    ("testSpeedingUpStretchesBehindTheLens", LiquidLensFlexTests.testSpeedingUpStretchesBehindTheLens),
    ("testNoVelocityNoDrift", LiquidLensFlexTests.testNoVelocityNoDrift),
    ("testSettlesBackToIdentity", LiquidLensFlexTests.testSettlesBackToIdentity),
])
run(LiquidLensMotionPlanTests.self, [
    (
        "testPlannedMovesInOppositeDirectionsAreMirrored",
        LiquidLensMotionPlanTests.testPlannedMovesInOppositeDirectionsAreMirrored,
    ),
    ("testPlanEndsAtRest", LiquidLensMotionPlanTests.testPlanEndsAtRest),
    ("testInterruptedPlanContinuesFromItsState", LiquidLensMotionPlanTests.testInterruptedPlanContinuesFromItsState),
    ("testPositionKeyframesFollowTheSegment", LiquidLensMotionPlanTests.testPositionKeyframesFollowTheSegment),
    ("testBezierProgressMatchesTheCurve", LiquidLensMotionPlanTests.testBezierProgressMatchesTheCurve),
    ("testRetargetCarriesVelocity", LiquidLensMotionPlanTests.testRetargetCarriesVelocity),
    ("testCarriedVelocityIsMirrored", LiquidLensMotionPlanTests.testCarriedVelocityIsMirrored),
    ("testRestingInactivePlanIsEmpty", LiquidLensMotionPlanTests.testRestingInactivePlanIsEmpty),
])
run(LiquidLensCurveTests.self, [
    ("testDefaultIsDisplaysSpringBezier", LiquidLensCurveTests.testDefaultIsDisplaysSpringBezier),
    ("testSpringEndsOnTarget", LiquidLensCurveTests.testSpringEndsOnTarget),
    ("testSpringShape", LiquidLensCurveTests.testSpringShape),
])
if failureCount > 0 {
    print("\(failureCount) assertion(s) failed.")
    exit(1)
}

print("All lens tests passed.")
