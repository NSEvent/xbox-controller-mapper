import SwiftUI
import GameController

// MARK: - Controller Body Shapes
//
// Each silhouette below was traced from a front-on product photo
// (potrace over a thresholded mask), so proportions and grip geometry
// match the real hardware. Paths are normalized to the unit rect;
// `aspectRatio` (width/height) is the traced bounding box ratio - render
// at a frame with this ratio to avoid distortion.

/// Xbox Series X|S controller silhouette (traced from product photo)
struct ControllerBodyShape: Shape {
    static let aspectRatio: CGFloat = 1.4256

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.2756, y: h * 0.0234))
        p.addCurve(to: CGPoint(x: w * 0.1020, y: h * 0.2923), control1: CGPoint(x: w * 0.1872, y: h * 0.0440), control2: CGPoint(x: w * 0.1560, y: h * 0.0919))
        p.addCurve(to: CGPoint(x: w * 0.0182, y: h * 0.8583), control1: CGPoint(x: w * 0.0274, y: h * 0.5695), control2: CGPoint(x: w * 0.0000, y: h * 0.7547))
        p.addCurve(to: CGPoint(x: w * 0.1058, y: h * 0.9834), control1: CGPoint(x: w * 0.0292, y: h * 0.9205), control2: CGPoint(x: w * 0.0730, y: h * 0.9832))
        p.addCurve(to: CGPoint(x: w * 0.2177, y: h * 0.8316), control1: CGPoint(x: w * 0.1253, y: h * 0.9834), control2: CGPoint(x: w * 0.1662, y: h * 0.9280))
        p.addCurve(to: CGPoint(x: w * 0.3135, y: h * 0.7175), control1: CGPoint(x: w * 0.2620, y: h * 0.7488), control2: CGPoint(x: w * 0.2784, y: h * 0.7294))
        p.addCurve(to: CGPoint(x: w * 0.6578, y: h * 0.7147), control1: CGPoint(x: w * 0.3256, y: h * 0.7135), control2: CGPoint(x: w * 0.6056, y: h * 0.7112))
        p.addCurve(to: CGPoint(x: w * 0.7751, y: h * 0.8255), control1: CGPoint(x: w * 0.7085, y: h * 0.7180), control2: CGPoint(x: w * 0.7269, y: h * 0.7355))
        p.addCurve(to: CGPoint(x: w * 0.8770, y: h * 0.9785), control1: CGPoint(x: w * 0.8194, y: h * 0.9083), control2: CGPoint(x: w * 0.8510, y: h * 0.9560))
        p.addCurve(to: CGPoint(x: w * 0.9728, y: h * 0.8793), control1: CGPoint(x: w * 0.9017, y: h * 1.0000), control2: CGPoint(x: w * 0.9557, y: h * 0.9441))
        p.addCurve(to: CGPoint(x: w * 0.8866, y: h * 0.2666), control1: CGPoint(x: w * 1.0000, y: h * 0.7764), control2: CGPoint(x: w * 0.9703, y: h * 0.5650))
        p.addCurve(to: CGPoint(x: w * 0.8294, y: h * 0.1055), control1: CGPoint(x: w * 0.8617, y: h * 0.1773), control2: CGPoint(x: w * 0.8576, y: h * 0.1658))
        p.addCurve(to: CGPoint(x: w * 0.6701, y: h * 0.0278), control1: CGPoint(x: w * 0.8018, y: h * 0.0463), control2: CGPoint(x: w * 0.7070, y: h * 0.0000))
        p.addCurve(to: CGPoint(x: w * 0.4979, y: h * 0.0468), control1: CGPoint(x: w * 0.6417, y: h * 0.0489), control2: CGPoint(x: w * 0.6619, y: h * 0.0468))
        p.addCurve(to: CGPoint(x: w * 0.3428, y: h * 0.0407), control1: CGPoint(x: w * 0.3510, y: h * 0.0468), control2: CGPoint(x: w * 0.3510, y: h * 0.0468))
        p.addCurve(to: CGPoint(x: w * 0.3036, y: h * 0.0208), control1: CGPoint(x: w * 0.3163, y: h * 0.0206), control2: CGPoint(x: w * 0.3176, y: h * 0.0213))
        p.addCurve(to: CGPoint(x: w * 0.2756, y: h * 0.0234), control1: CGPoint(x: w * 0.2964, y: h * 0.0203), control2: CGPoint(x: w * 0.2838, y: h * 0.0215))
        p.closeSubpath()
        return p
    }
}

/// Xbox Elite Series 2 controller silhouette (traced from product photo)
struct XboxEliteBodyShape: Shape {
    static let aspectRatio: CGFloat = 1.4614

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.3024, y: h * 0.0048))
        p.addCurve(to: CGPoint(x: w * 0.2439, y: h * 0.0268), control1: CGPoint(x: w * 0.2789, y: h * 0.0104), control2: CGPoint(x: w * 0.2522, y: h * 0.0204))
        p.addCurve(to: CGPoint(x: w * 0.2306, y: h * 0.0503), control1: CGPoint(x: w * 0.2376, y: h * 0.0318), control2: CGPoint(x: w * 0.2358, y: h * 0.0347))
        p.addCurve(to: CGPoint(x: w * 0.2028, y: h * 0.0685), control1: CGPoint(x: w * 0.2228, y: h * 0.0733), control2: CGPoint(x: w * 0.2122, y: h * 0.0803))
        p.addCurve(to: CGPoint(x: w * 0.1695, y: h * 0.0971), control1: CGPoint(x: w * 0.1924, y: h * 0.0556), control2: CGPoint(x: w * 0.1805, y: h * 0.0658))
        p.addCurve(to: CGPoint(x: w * 0.1548, y: h * 0.1268), control1: CGPoint(x: w * 0.1654, y: h * 0.1093), control2: CGPoint(x: w * 0.1628, y: h * 0.1145))
        p.addCurve(to: CGPoint(x: w * 0.1300, y: h * 0.1747), control1: CGPoint(x: w * 0.1427, y: h * 0.1452), control2: CGPoint(x: w * 0.1342, y: h * 0.1618))
        p.addCurve(to: CGPoint(x: w * 0.1112, y: h * 0.2429), control1: CGPoint(x: w * 0.1260, y: h * 0.1876), control2: CGPoint(x: w * 0.1150, y: h * 0.2275))
        p.addCurve(to: CGPoint(x: w * 0.1026, y: h * 0.2751), control1: CGPoint(x: w * 0.1096, y: h * 0.2496), control2: CGPoint(x: w * 0.1057, y: h * 0.2642))
        p.addCurve(to: CGPoint(x: w * 0.0850, y: h * 0.3472), control1: CGPoint(x: w * 0.0951, y: h * 0.3011), control2: CGPoint(x: w * 0.0902, y: h * 0.3217))
        p.addCurve(to: CGPoint(x: w * 0.0748, y: h * 0.3953), control1: CGPoint(x: w * 0.0828, y: h * 0.3584), control2: CGPoint(x: w * 0.0782, y: h * 0.3801))
        p.addCurve(to: CGPoint(x: w * 0.0385, y: h * 0.5690), control1: CGPoint(x: w * 0.0617, y: h * 0.4543), control2: CGPoint(x: w * 0.0422, y: h * 0.5479))
        p.addCurve(to: CGPoint(x: w * 0.0962, y: h * 0.9772), control1: CGPoint(x: w * 0.0000, y: h * 0.7935), control2: CGPoint(x: w * 0.0179, y: h * 0.9200))
        p.addCurve(to: CGPoint(x: w * 0.2092, y: h * 0.8619), control1: CGPoint(x: w * 0.1275, y: h * 1.0000), control2: CGPoint(x: w * 0.1454, y: h * 0.9818))
        p.addCurve(to: CGPoint(x: w * 0.2697, y: h * 0.7715), control1: CGPoint(x: w * 0.2515, y: h * 0.7826), control2: CGPoint(x: w * 0.2544, y: h * 0.7782))
        p.addCurve(to: CGPoint(x: w * 0.2866, y: h * 0.7488), control1: CGPoint(x: w * 0.2758, y: h * 0.7688), control2: CGPoint(x: w * 0.2801, y: h * 0.7632))
        p.addCurve(to: CGPoint(x: w * 0.5310, y: h * 0.7164), control1: CGPoint(x: w * 0.3017, y: h * 0.7151), control2: CGPoint(x: w * 0.3001, y: h * 0.7154))
        p.addCurve(to: CGPoint(x: w * 0.7208, y: h * 0.7528), control1: CGPoint(x: w * 0.7099, y: h * 0.7171), control2: CGPoint(x: w * 0.7061, y: h * 0.7164))
        p.addCurve(to: CGPoint(x: w * 0.7369, y: h * 0.7727), control1: CGPoint(x: w * 0.7255, y: h * 0.7647), control2: CGPoint(x: w * 0.7286, y: h * 0.7685))
        p.addCurve(to: CGPoint(x: w * 0.8027, y: h * 0.8760), control1: CGPoint(x: w * 0.7504, y: h * 0.7790), control2: CGPoint(x: w * 0.7600, y: h * 0.7942))
        p.addCurve(to: CGPoint(x: w * 0.9012, y: h * 0.9817), control1: CGPoint(x: w * 0.8512, y: h * 0.9691), control2: CGPoint(x: w * 0.8768, y: h * 0.9966))
        p.addCurve(to: CGPoint(x: w * 0.9753, y: h * 0.6328), control1: CGPoint(x: w * 0.9774, y: h * 0.9350), control2: CGPoint(x: w * 1.0000, y: h * 0.8287))
        p.addCurve(to: CGPoint(x: w * 0.9392, y: h * 0.4378), control1: CGPoint(x: w * 0.9679, y: h * 0.5740), control2: CGPoint(x: w * 0.9626, y: h * 0.5453))
        p.addCurve(to: CGPoint(x: w * 0.9256, y: h * 0.3733), control1: CGPoint(x: w * 0.9339, y: h * 0.4133), control2: CGPoint(x: w * 0.9277, y: h * 0.3842))
        p.addCurve(to: CGPoint(x: w * 0.8893, y: h * 0.2258), control1: CGPoint(x: w * 0.9190, y: h * 0.3405), control2: CGPoint(x: w * 0.9106, y: h * 0.3068))
        p.addCurve(to: CGPoint(x: w * 0.8486, y: h * 0.1248), control1: CGPoint(x: w * 0.8732, y: h * 0.1645), control2: CGPoint(x: w * 0.8719, y: h * 0.1613))
        p.addCurve(to: CGPoint(x: w * 0.8342, y: h * 0.0959), control1: CGPoint(x: w * 0.8412, y: h * 0.1133), control2: CGPoint(x: w * 0.8383, y: h * 0.1075))
        p.addCurve(to: CGPoint(x: w * 0.8041, y: h * 0.0634), control1: CGPoint(x: w * 0.8249, y: h * 0.0695), control2: CGPoint(x: w * 0.8162, y: h * 0.0601))
        p.addCurve(to: CGPoint(x: w * 0.7878, y: h * 0.0519), control1: CGPoint(x: w * 0.7956, y: h * 0.0658), control2: CGPoint(x: w * 0.7944, y: h * 0.0650))
        p.addCurve(to: CGPoint(x: w * 0.7260, y: h * 0.0118), control1: CGPoint(x: w * 0.7785, y: h * 0.0338), control2: CGPoint(x: w * 0.7641, y: h * 0.0244))
        p.addCurve(to: CGPoint(x: w * 0.6576, y: h * 0.0173), control1: CGPoint(x: w * 0.6906, y: h * 0.0000), control2: CGPoint(x: w * 0.6817, y: h * 0.0007))
        p.addCurve(to: CGPoint(x: w * 0.6382, y: h * 0.0295), control1: CGPoint(x: w * 0.6494, y: h * 0.0231), control2: CGPoint(x: w * 0.6406, y: h * 0.0285))
        p.addCurve(to: CGPoint(x: w * 0.5013, y: h * 0.0311), control1: CGPoint(x: w * 0.6349, y: h * 0.0308), control2: CGPoint(x: w * 0.6016, y: h * 0.0312))
        p.addCurve(to: CGPoint(x: w * 0.3467, y: h * 0.0173), control1: CGPoint(x: w * 0.3497, y: h * 0.0309), control2: CGPoint(x: w * 0.3661, y: h * 0.0323))
        p.addCurve(to: CGPoint(x: w * 0.3024, y: h * 0.0048), control1: CGPoint(x: w * 0.3308, y: h * 0.0051), control2: CGPoint(x: w * 0.3174, y: h * 0.0013))
        p.closeSubpath()
        return p
    }
}

/// DualSense controller silhouette (traced from product photo)
struct DualSenseBodyShape: Shape {
    static let aspectRatio: CGFloat = 1.5142

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.1955, y: h * 0.0218))
        p.addCurve(to: CGPoint(x: w * 0.1342, y: h * 0.0688), control1: CGPoint(x: w * 0.1663, y: h * 0.0297), control2: CGPoint(x: w * 0.1434, y: h * 0.0474))
        p.addCurve(to: CGPoint(x: w * 0.1199, y: h * 0.0937), control1: CGPoint(x: w * 0.1308, y: h * 0.0767), control2: CGPoint(x: w * 0.1244, y: h * 0.0878))
        p.addCurve(to: CGPoint(x: w * 0.0176, y: h * 0.5874), control1: CGPoint(x: w * 0.0876, y: h * 0.1354), control2: CGPoint(x: w * 0.0306, y: h * 0.4109))
        p.addCurve(to: CGPoint(x: w * 0.0942, y: h * 0.9827), control1: CGPoint(x: w * 0.0000, y: h * 0.8279), control2: CGPoint(x: w * 0.0270, y: h * 0.9679))
        p.addCurve(to: CGPoint(x: w * 0.1206, y: h * 0.9895), control1: CGPoint(x: w * 0.1027, y: h * 0.9847), control2: CGPoint(x: w * 0.1147, y: h * 0.9878))
        p.addCurve(to: CGPoint(x: w * 0.2151, y: h * 0.7709), control1: CGPoint(x: w * 0.1571, y: h * 1.0000), control2: CGPoint(x: w * 0.1578, y: h * 0.9985))
        p.addCurve(to: CGPoint(x: w * 0.3208, y: h * 0.6527), control1: CGPoint(x: w * 0.2399, y: h * 0.6723), control2: CGPoint(x: w * 0.2677, y: h * 0.6413))
        p.addCurve(to: CGPoint(x: w * 0.6792, y: h * 0.6527), control1: CGPoint(x: w * 0.3452, y: h * 0.6579), control2: CGPoint(x: w * 0.6548, y: h * 0.6579))
        p.addCurve(to: CGPoint(x: w * 0.7856, y: h * 0.7741), control1: CGPoint(x: w * 0.7328, y: h * 0.6411), control2: CGPoint(x: w * 0.7600, y: h * 0.6721))
        p.addCurve(to: CGPoint(x: w * 0.8794, y: h * 0.9895), control1: CGPoint(x: w * 0.8417, y: h * 0.9969), control2: CGPoint(x: w * 0.8430, y: h * 1.0000))
        p.addCurve(to: CGPoint(x: w * 0.9058, y: h * 0.9827), control1: CGPoint(x: w * 0.8853, y: h * 0.9878), control2: CGPoint(x: w * 0.8973, y: h * 0.9847))
        p.addCurve(to: CGPoint(x: w * 0.9824, y: h * 0.5874), control1: CGPoint(x: w * 0.9730, y: h * 0.9679), control2: CGPoint(x: w * 1.0000, y: h * 0.8279))
        p.addCurve(to: CGPoint(x: w * 0.8801, y: h * 0.0937), control1: CGPoint(x: w * 0.9694, y: h * 0.4109), control2: CGPoint(x: w * 0.9124, y: h * 0.1354))
        p.addCurve(to: CGPoint(x: w * 0.8658, y: h * 0.0688), control1: CGPoint(x: w * 0.8756, y: h * 0.0878), control2: CGPoint(x: w * 0.8692, y: h * 0.0767))
        p.addCurve(to: CGPoint(x: w * 0.7387, y: h * 0.0371), control1: CGPoint(x: w * 0.8451, y: h * 0.0205), control2: CGPoint(x: w * 0.7624, y: h * 0.0000))
        p.addCurve(to: CGPoint(x: w * 0.6859, y: h * 0.0448), control1: CGPoint(x: w * 0.7279, y: h * 0.0542), control2: CGPoint(x: w * 0.7288, y: h * 0.0540))
        p.addCurve(to: CGPoint(x: w * 0.5000, y: h * 0.0293), control1: CGPoint(x: w * 0.6357, y: h * 0.0339), control2: CGPoint(x: w * 0.5805, y: h * 0.0293))
        p.addCurve(to: CGPoint(x: w * 0.3141, y: h * 0.0448), control1: CGPoint(x: w * 0.4195, y: h * 0.0293), control2: CGPoint(x: w * 0.3643, y: h * 0.0339))
        p.addCurve(to: CGPoint(x: w * 0.2613, y: h * 0.0371), control1: CGPoint(x: w * 0.2712, y: h * 0.0540), control2: CGPoint(x: w * 0.2721, y: h * 0.0542))
        p.addCurve(to: CGPoint(x: w * 0.1955, y: h * 0.0218), control1: CGPoint(x: w * 0.2491, y: h * 0.0179), control2: CGPoint(x: w * 0.2276, y: h * 0.0129))
        p.closeSubpath()
        return p
    }
}

/// DualShock 4 controller silhouette (traced from product photo)
struct DualShockBodyShape: Shape {
    static let aspectRatio: CGFloat = 1.5980

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.3847, y: h * 0.0007))
        p.addCurve(to: CGPoint(x: w * 0.3737, y: h * 0.0429), control1: CGPoint(x: w * 0.3750, y: h * 0.0027), control2: CGPoint(x: w * 0.3737, y: h * 0.0075))
        p.addCurve(to: CGPoint(x: w * 0.3719, y: h * 0.0789), control1: CGPoint(x: w * 0.3737, y: h * 0.0661), control2: CGPoint(x: w * 0.3735, y: h * 0.0704))
        p.addCurve(to: CGPoint(x: w * 0.3719, y: h * 0.0979), control1: CGPoint(x: w * 0.3705, y: h * 0.0867), control2: CGPoint(x: w * 0.3705, y: h * 0.0901))
        p.addCurve(to: CGPoint(x: w * 0.3736, y: h * 0.2187), control1: CGPoint(x: w * 0.3738, y: h * 0.1080), control2: CGPoint(x: w * 0.3737, y: h * 0.1073))
        p.addCurve(to: CGPoint(x: w * 0.3730, y: h * 0.3245), control1: CGPoint(x: w * 0.3735, y: h * 0.3104), control2: CGPoint(x: w * 0.3734, y: h * 0.3221))
        p.addCurve(to: CGPoint(x: w * 0.3558, y: h * 0.3387), control1: CGPoint(x: w * 0.3710, y: h * 0.3347), control2: CGPoint(x: w * 0.3663, y: h * 0.3386))
        p.addCurve(to: CGPoint(x: w * 0.3324, y: h * 0.3062), control1: CGPoint(x: w * 0.3438, y: h * 0.3389), control2: CGPoint(x: w * 0.3353, y: h * 0.3272))
        p.addCurve(to: CGPoint(x: w * 0.3324, y: h * 0.0610), control1: CGPoint(x: w * 0.3312, y: h * 0.2976), control2: CGPoint(x: w * 0.3312, y: h * 0.0772))
        p.addCurve(to: CGPoint(x: w * 0.3002, y: h * 0.0315), control1: CGPoint(x: w * 0.3344, y: h * 0.0344), control2: CGPoint(x: w * 0.3283, y: h * 0.0289))
        p.addCurve(to: CGPoint(x: w * 0.2700, y: h * 0.0273), control1: CGPoint(x: w * 0.2867, y: h * 0.0328), control2: CGPoint(x: w * 0.2770, y: h * 0.0314))
        p.addCurve(to: CGPoint(x: w * 0.2545, y: h * 0.0226), control1: CGPoint(x: w * 0.2641, y: h * 0.0237), control2: CGPoint(x: w * 0.2625, y: h * 0.0232))
        p.addCurve(to: CGPoint(x: w * 0.2427, y: h * 0.0213), control1: CGPoint(x: w * 0.2507, y: h * 0.0223), control2: CGPoint(x: w * 0.2454, y: h * 0.0217))
        p.addCurve(to: CGPoint(x: w * 0.1617, y: h * 0.0215), control1: CGPoint(x: w * 0.2241, y: h * 0.0181), control2: CGPoint(x: w * 0.1952, y: h * 0.0182))
        p.addCurve(to: CGPoint(x: w * 0.1417, y: h * 0.0242), control1: CGPoint(x: w * 0.1507, y: h * 0.0226), control2: CGPoint(x: w * 0.1458, y: h * 0.0233))
        p.addCurve(to: CGPoint(x: w * 0.1331, y: h * 0.0256), control1: CGPoint(x: w * 0.1404, y: h * 0.0245), control2: CGPoint(x: w * 0.1366, y: h * 0.0251))
        p.addCurve(to: CGPoint(x: w * 0.1130, y: h * 0.0490), control1: CGPoint(x: w * 0.1206, y: h * 0.0273), control2: CGPoint(x: w * 0.1194, y: h * 0.0287))
        p.addCurve(to: CGPoint(x: w * 0.1038, y: h * 0.0733), control1: CGPoint(x: w * 0.1087, y: h * 0.0625), control2: CGPoint(x: w * 0.1077, y: h * 0.0653))
        p.addCurve(to: CGPoint(x: w * 0.0991, y: h * 0.0846), control1: CGPoint(x: w * 0.1025, y: h * 0.0760), control2: CGPoint(x: w * 0.1004, y: h * 0.0811))
        p.addCurve(to: CGPoint(x: w * 0.0932, y: h * 0.0984), control1: CGPoint(x: w * 0.0978, y: h * 0.0880), control2: CGPoint(x: w * 0.0951, y: h * 0.0942))
        p.addCurve(to: CGPoint(x: w * 0.0784, y: h * 0.1389), control1: CGPoint(x: w * 0.0893, y: h * 0.1066), control2: CGPoint(x: w * 0.0806, y: h * 0.1305))
        p.addCurve(to: CGPoint(x: w * 0.0760, y: h * 0.1482), control1: CGPoint(x: w * 0.0777, y: h * 0.1415), control2: CGPoint(x: w * 0.0766, y: h * 0.1456))
        p.addCurve(to: CGPoint(x: w * 0.0719, y: h * 0.1628), control1: CGPoint(x: w * 0.0753, y: h * 0.1508), control2: CGPoint(x: w * 0.0735, y: h * 0.1574))
        p.addCurve(to: CGPoint(x: w * 0.0652, y: h * 0.1902), control1: CGPoint(x: w * 0.0689, y: h * 0.1732), control2: CGPoint(x: w * 0.0681, y: h * 0.1764))
        p.addCurve(to: CGPoint(x: w * 0.0625, y: h * 0.2022), control1: CGPoint(x: w * 0.0642, y: h * 0.1947), control2: CGPoint(x: w * 0.0631, y: h * 0.2001))
        p.addCurve(to: CGPoint(x: w * 0.0601, y: h * 0.2135), control1: CGPoint(x: w * 0.0620, y: h * 0.2043), control2: CGPoint(x: w * 0.0610, y: h * 0.2094))
        p.addCurve(to: CGPoint(x: w * 0.0574, y: h * 0.2264), control1: CGPoint(x: w * 0.0593, y: h * 0.2175), control2: CGPoint(x: w * 0.0581, y: h * 0.2233))
        p.addCurve(to: CGPoint(x: w * 0.0552, y: h * 0.2415), control1: CGPoint(x: w * 0.0566, y: h * 0.2299), control2: CGPoint(x: w * 0.0558, y: h * 0.2352))
        p.addCurve(to: CGPoint(x: w * 0.0527, y: h * 0.2580), control1: CGPoint(x: w * 0.0545, y: h * 0.2483), control2: CGPoint(x: w * 0.0537, y: h * 0.2531))
        p.addCurve(to: CGPoint(x: w * 0.0493, y: h * 0.2790), control1: CGPoint(x: w * 0.0509, y: h * 0.2657), control2: CGPoint(x: w * 0.0503, y: h * 0.2696))
        p.addCurve(to: CGPoint(x: w * 0.0469, y: h * 0.2935), control1: CGPoint(x: w * 0.0489, y: h * 0.2828), control2: CGPoint(x: w * 0.0479, y: h * 0.2889))
        p.addCurve(to: CGPoint(x: w * 0.0437, y: h * 0.3173), control1: CGPoint(x: w * 0.0453, y: h * 0.3013), control2: CGPoint(x: w * 0.0448, y: h * 0.3050))
        p.addCurve(to: CGPoint(x: w * 0.0413, y: h * 0.3321), control1: CGPoint(x: w * 0.0433, y: h * 0.3213), control2: CGPoint(x: w * 0.0425, y: h * 0.3262))
        p.addCurve(to: CGPoint(x: w * 0.0385, y: h * 0.3484), control1: CGPoint(x: w * 0.0403, y: h * 0.3370), control2: CGPoint(x: w * 0.0390, y: h * 0.3443))
        p.addCurve(to: CGPoint(x: w * 0.0366, y: h * 0.3613), control1: CGPoint(x: w * 0.0380, y: h * 0.3525), control2: CGPoint(x: w * 0.0371, y: h * 0.3583))
        p.addCurve(to: CGPoint(x: w * 0.0337, y: h * 0.3806), control1: CGPoint(x: w * 0.0349, y: h * 0.3700), control2: CGPoint(x: w * 0.0346, y: h * 0.3718))
        p.addCurve(to: CGPoint(x: w * 0.0312, y: h * 0.3973), control1: CGPoint(x: w * 0.0332, y: h * 0.3858), control2: CGPoint(x: w * 0.0322, y: h * 0.3922))
        p.addCurve(to: CGPoint(x: w * 0.0287, y: h * 0.4131), control1: CGPoint(x: w * 0.0301, y: h * 0.4024), control2: CGPoint(x: w * 0.0292, y: h * 0.4087))
        p.addCurve(to: CGPoint(x: w * 0.0256, y: h * 0.4340), control1: CGPoint(x: w * 0.0279, y: h * 0.4217), control2: CGPoint(x: w * 0.0275, y: h * 0.4246))
        p.addCurve(to: CGPoint(x: w * 0.0230, y: h * 0.4523), control1: CGPoint(x: w * 0.0247, y: h * 0.4385), control2: CGPoint(x: w * 0.0238, y: h * 0.4448))
        p.addCurve(to: CGPoint(x: w * 0.0198, y: h * 0.4773), control1: CGPoint(x: w * 0.0224, y: h * 0.4586), control2: CGPoint(x: w * 0.0209, y: h * 0.4699))
        p.addCurve(to: CGPoint(x: w * 0.0169, y: h * 0.4981), control1: CGPoint(x: w * 0.0187, y: h * 0.4847), control2: CGPoint(x: w * 0.0174, y: h * 0.4941))
        p.addCurve(to: CGPoint(x: w * 0.0143, y: h * 0.5138), control1: CGPoint(x: w * 0.0164, y: h * 0.5022), control2: CGPoint(x: w * 0.0152, y: h * 0.5092))
        p.addCurve(to: CGPoint(x: w * 0.0114, y: h * 0.5382), control1: CGPoint(x: w * 0.0120, y: h * 0.5250), control2: CGPoint(x: w * 0.0120, y: h * 0.5254))
        p.addCurve(to: CGPoint(x: w * 0.0083, y: h * 0.5648), control1: CGPoint(x: w * 0.0108, y: h * 0.5514), control2: CGPoint(x: w * 0.0104, y: h * 0.5545))
        p.addCurve(to: CGPoint(x: w * 0.0057, y: h * 0.5943), control1: CGPoint(x: w * 0.0060, y: h * 0.5757), control2: CGPoint(x: w * 0.0058, y: h * 0.5785))
        p.addCurve(to: CGPoint(x: w * 0.0030, y: h * 0.6281), control1: CGPoint(x: w * 0.0057, y: h * 0.6130), control2: CGPoint(x: w * 0.0055, y: h * 0.6164))
        p.addCurve(to: CGPoint(x: w * 0.0003, y: h * 0.7203), control1: CGPoint(x: w * 0.0000, y: h * 0.6423), control2: CGPoint(x: w * 0.0002, y: h * 0.6372))
        p.addCurve(to: CGPoint(x: w * 0.0003, y: h * 0.8072), control1: CGPoint(x: w * 0.0003, y: h * 0.7605), control2: CGPoint(x: w * 0.0003, y: h * 0.7996))
        p.addCurve(to: CGPoint(x: w * 0.0028, y: h * 0.8363), control1: CGPoint(x: w * 0.0001, y: h * 0.8230), control2: CGPoint(x: w * 0.0003, y: h * 0.8254))
        p.addCurve(to: CGPoint(x: w * 0.0057, y: h * 0.8514), control1: CGPoint(x: w * 0.0037, y: h * 0.8398), control2: CGPoint(x: w * 0.0050, y: h * 0.8466))
        p.addCurve(to: CGPoint(x: w * 0.0305, y: h * 0.9238), control1: CGPoint(x: w * 0.0084, y: h * 0.8678), control2: CGPoint(x: w * 0.0209, y: h * 0.9045))
        p.addCurve(to: CGPoint(x: w * 0.1549, y: h * 0.9592), control1: CGPoint(x: w * 0.0611, y: h * 0.9856), control2: CGPoint(x: w * 0.1118, y: h * 1.0000))
        p.addCurve(to: CGPoint(x: w * 0.1872, y: h * 0.9100), control1: CGPoint(x: w * 0.1666, y: h * 0.9481), control2: CGPoint(x: w * 0.1764, y: h * 0.9331))
        p.addCurve(to: CGPoint(x: w * 0.2119, y: h * 0.8459), control1: CGPoint(x: w * 0.1962, y: h * 0.8908), control2: CGPoint(x: w * 0.1989, y: h * 0.8836))
        p.addCurve(to: CGPoint(x: w * 0.2186, y: h * 0.8281), control1: CGPoint(x: w * 0.2134, y: h * 0.8415), control2: CGPoint(x: w * 0.2164, y: h * 0.8335))
        p.addCurve(to: CGPoint(x: w * 0.2270, y: h * 0.8015), control1: CGPoint(x: w * 0.2234, y: h * 0.8166), control2: CGPoint(x: w * 0.2243, y: h * 0.8136))
        p.addCurve(to: CGPoint(x: w * 0.2326, y: h * 0.7790), control1: CGPoint(x: w * 0.2295, y: h * 0.7896), control2: CGPoint(x: w * 0.2299, y: h * 0.7883))
        p.addCurve(to: CGPoint(x: w * 0.2368, y: h * 0.7625), control1: CGPoint(x: w * 0.2339, y: h * 0.7746), control2: CGPoint(x: w * 0.2358, y: h * 0.7672))
        p.addCurve(to: CGPoint(x: w * 0.2415, y: h * 0.7425), control1: CGPoint(x: w * 0.2379, y: h * 0.7578), control2: CGPoint(x: w * 0.2400, y: h * 0.7488))
        p.addCurve(to: CGPoint(x: w * 0.2467, y: h * 0.7205), control1: CGPoint(x: w * 0.2431, y: h * 0.7361), control2: CGPoint(x: w * 0.2454, y: h * 0.7263))
        p.addCurve(to: CGPoint(x: w * 0.2506, y: h * 0.7041), control1: CGPoint(x: w * 0.2480, y: h * 0.7148), control2: CGPoint(x: w * 0.2497, y: h * 0.7074))
        p.addCurve(to: CGPoint(x: w * 0.2534, y: h * 0.6907), control1: CGPoint(x: w * 0.2515, y: h * 0.7007), control2: CGPoint(x: w * 0.2527, y: h * 0.6947))
        p.addCurve(to: CGPoint(x: w * 0.2891, y: h * 0.6496), control1: CGPoint(x: w * 0.2620, y: h * 0.6387), control2: CGPoint(x: w * 0.2691, y: h * 0.6305))
        p.addCurve(to: CGPoint(x: w * 0.3052, y: h * 0.6624), control1: CGPoint(x: w * 0.2977, y: h * 0.6579), control2: CGPoint(x: w * 0.3009, y: h * 0.6603))
        p.addCurve(to: CGPoint(x: w * 0.3129, y: h * 0.6662), control1: CGPoint(x: w * 0.3069, y: h * 0.6632), control2: CGPoint(x: w * 0.3104, y: h * 0.6649))
        p.addCurve(to: CGPoint(x: w * 0.3665, y: h * 0.6681), control1: CGPoint(x: w * 0.3253, y: h * 0.6726), control2: CGPoint(x: w * 0.3572, y: h * 0.6737))
        p.addCurve(to: CGPoint(x: w * 0.3752, y: h * 0.6632), control1: CGPoint(x: w * 0.3681, y: h * 0.6672), control2: CGPoint(x: w * 0.3720, y: h * 0.6650))
        p.addCurve(to: CGPoint(x: w * 0.4080, y: h * 0.6365), control1: CGPoint(x: w * 0.3849, y: h * 0.6579), control2: CGPoint(x: w * 0.3980, y: h * 0.6473))
        p.addCurve(to: CGPoint(x: w * 0.4314, y: h * 0.6276), control1: CGPoint(x: w * 0.4152, y: h * 0.6288), control2: CGPoint(x: w * 0.4168, y: h * 0.6282))
        p.addCurve(to: CGPoint(x: w * 0.4518, y: h * 0.6196), control1: CGPoint(x: w * 0.4455, y: h * 0.6270), control2: CGPoint(x: w * 0.4466, y: h * 0.6266))
        p.addCurve(to: CGPoint(x: w * 0.5021, y: h * 0.6085), control1: CGPoint(x: w * 0.4605, y: h * 0.6079), control2: CGPoint(x: w * 0.4590, y: h * 0.6083))
        p.addCurve(to: CGPoint(x: w * 0.5467, y: h * 0.6188), control1: CGPoint(x: w * 0.5410, y: h * 0.6087), control2: CGPoint(x: w * 0.5388, y: h * 0.6082))
        p.addCurve(to: CGPoint(x: w * 0.5692, y: h * 0.6281), control1: CGPoint(x: w * 0.5529, y: h * 0.6271), control2: CGPoint(x: w * 0.5540, y: h * 0.6276))
        p.addCurve(to: CGPoint(x: w * 0.5925, y: h * 0.6381), control1: CGPoint(x: w * 0.5839, y: h * 0.6286), control2: CGPoint(x: w * 0.5837, y: h * 0.6285))
        p.addCurve(to: CGPoint(x: w * 0.6225, y: h * 0.6616), control1: CGPoint(x: w * 0.6003, y: h * 0.6464), control2: CGPoint(x: w * 0.6136, y: h * 0.6569))
        p.addCurve(to: CGPoint(x: w * 0.6311, y: h * 0.6665), control1: CGPoint(x: w * 0.6253, y: h * 0.6630), control2: CGPoint(x: w * 0.6291, y: h * 0.6653))
        p.addCurve(to: CGPoint(x: w * 0.6494, y: h * 0.6713), control1: CGPoint(x: w * 0.6381, y: h * 0.6711), control2: CGPoint(x: w * 0.6380, y: h * 0.6711))
        p.addCurve(to: CGPoint(x: w * 0.6870, y: h * 0.6646), control1: CGPoint(x: w * 0.6684, y: h * 0.6717), control2: CGPoint(x: w * 0.6733, y: h * 0.6709))
        p.addCurve(to: CGPoint(x: w * 0.7101, y: h * 0.6494), control1: CGPoint(x: w * 0.6976, y: h * 0.6598), control2: CGPoint(x: w * 0.6973, y: h * 0.6600))
        p.addCurve(to: CGPoint(x: w * 0.7265, y: h * 0.6401), control1: CGPoint(x: w * 0.7210, y: h * 0.6404), control2: CGPoint(x: w * 0.7233, y: h * 0.6390))
        p.addCurve(to: CGPoint(x: w * 0.7417, y: h * 0.6678), control1: CGPoint(x: w * 0.7330, y: h * 0.6423), control2: CGPoint(x: w * 0.7388, y: h * 0.6530))
        p.addCurve(to: CGPoint(x: w * 0.7446, y: h * 0.6805), control1: CGPoint(x: w * 0.7423, y: h * 0.6709), control2: CGPoint(x: w * 0.7436, y: h * 0.6766))
        p.addCurve(to: CGPoint(x: w * 0.7528, y: h * 0.7203), control1: CGPoint(x: w * 0.7468, y: h * 0.6891), control2: CGPoint(x: w * 0.7516, y: h * 0.7123))
        p.addCurve(to: CGPoint(x: w * 0.7553, y: h * 0.7323), control1: CGPoint(x: w * 0.7533, y: h * 0.7235), control2: CGPoint(x: w * 0.7544, y: h * 0.7289))
        p.addCurve(to: CGPoint(x: w * 0.7586, y: h * 0.7471), control1: CGPoint(x: w * 0.7561, y: h * 0.7358), control2: CGPoint(x: w * 0.7576, y: h * 0.7425))
        p.addCurve(to: CGPoint(x: w * 0.7660, y: h * 0.7751), control1: CGPoint(x: w * 0.7608, y: h * 0.7572), control2: CGPoint(x: w * 0.7628, y: h * 0.7649))
        p.addCurve(to: CGPoint(x: w * 0.7738, y: h * 0.8053), control1: CGPoint(x: w * 0.7686, y: h * 0.7832), control2: CGPoint(x: w * 0.7717, y: h * 0.7955))
        p.addCurve(to: CGPoint(x: w * 0.7802, y: h * 0.8253), control1: CGPoint(x: w * 0.7756, y: h * 0.8135), control2: CGPoint(x: w * 0.7768, y: h * 0.8171))
        p.addCurve(to: CGPoint(x: w * 0.7896, y: h * 0.8514), control1: CGPoint(x: w * 0.7834, y: h * 0.8328), control2: CGPoint(x: w * 0.7836, y: h * 0.8330))
        p.addCurve(to: CGPoint(x: w * 0.9139, y: h * 0.9791), control1: CGPoint(x: w * 0.8237, y: h * 0.9541), control2: CGPoint(x: w * 0.8641, y: h * 0.9957))
        p.addCurve(to: CGPoint(x: w * 0.9938, y: h * 0.8503), control1: CGPoint(x: w * 0.9515, y: h * 0.9667), control2: CGPoint(x: w * 0.9864, y: h * 0.9104))
        p.addCurve(to: CGPoint(x: w * 0.9965, y: h * 0.8328), control1: CGPoint(x: w * 0.9945, y: h * 0.8447), control2: CGPoint(x: w * 0.9957, y: h * 0.8368))
        p.addCurve(to: CGPoint(x: w * 0.9996, y: h * 0.7455), control1: CGPoint(x: w * 0.9996, y: h * 0.8180), control2: CGPoint(x: w * 0.9994, y: h * 0.8221))
        p.addCurve(to: CGPoint(x: w * 0.9972, y: h * 0.6300), control1: CGPoint(x: w * 0.9999, y: h * 0.6372), control2: CGPoint(x: w * 1.0000, y: h * 0.6432))
        p.addCurve(to: CGPoint(x: w * 0.9939, y: h * 0.5955), control1: CGPoint(x: w * 0.9946, y: h * 0.6183), control2: CGPoint(x: w * 0.9945, y: h * 0.6169))
        p.addCurve(to: CGPoint(x: w * 0.9917, y: h * 0.5704), control1: CGPoint(x: w * 0.9935, y: h * 0.5812), control2: CGPoint(x: w * 0.9933, y: h * 0.5785))
        p.addCurve(to: CGPoint(x: w * 0.9889, y: h * 0.5461), control1: CGPoint(x: w * 0.9898, y: h * 0.5608), control2: CGPoint(x: w * 0.9895, y: h * 0.5584))
        p.addCurve(to: CGPoint(x: w * 0.9862, y: h * 0.5223), control1: CGPoint(x: w * 0.9884, y: h * 0.5337), control2: CGPoint(x: w * 0.9881, y: h * 0.5310))
        p.addCurve(to: CGPoint(x: w * 0.9835, y: h * 0.5009), control1: CGPoint(x: w * 0.9845, y: h * 0.5144), control2: CGPoint(x: w * 0.9841, y: h * 0.5112))
        p.addCurve(to: CGPoint(x: w * 0.9804, y: h * 0.4787), control1: CGPoint(x: w * 0.9829, y: h * 0.4908), control2: CGPoint(x: w * 0.9826, y: h * 0.4885))
        p.addCurve(to: CGPoint(x: w * 0.9773, y: h * 0.4556), control1: CGPoint(x: w * 0.9788, y: h * 0.4718), control2: CGPoint(x: w * 0.9783, y: h * 0.4677))
        p.addCurve(to: CGPoint(x: w * 0.9749, y: h * 0.4402), control1: CGPoint(x: w * 0.9769, y: h * 0.4508), control2: CGPoint(x: w * 0.9762, y: h * 0.4466))
        p.addCurve(to: CGPoint(x: w * 0.9720, y: h * 0.4232), control1: CGPoint(x: w * 0.9739, y: h * 0.4353), control2: CGPoint(x: w * 0.9725, y: h * 0.4277))
        p.addCurve(to: CGPoint(x: w * 0.9694, y: h * 0.4068), control1: CGPoint(x: w * 0.9714, y: h * 0.4187), control2: CGPoint(x: w * 0.9702, y: h * 0.4113))
        p.addCurve(to: CGPoint(x: w * 0.9675, y: h * 0.3934), control1: CGPoint(x: w * 0.9686, y: h * 0.4023), control2: CGPoint(x: w * 0.9677, y: h * 0.3962))
        p.addCurve(to: CGPoint(x: w * 0.9644, y: h * 0.3687), control1: CGPoint(x: w * 0.9663, y: h * 0.3782), control2: CGPoint(x: w * 0.9661, y: h * 0.3761))
        p.addCurve(to: CGPoint(x: w * 0.9608, y: h * 0.3481), control1: CGPoint(x: w * 0.9621, y: h * 0.3588), control2: CGPoint(x: w * 0.9618, y: h * 0.3571))
        p.addCurve(to: CGPoint(x: w * 0.9591, y: h * 0.3355), control1: CGPoint(x: w * 0.9604, y: h * 0.3438), control2: CGPoint(x: w * 0.9595, y: h * 0.3381))
        p.addCurve(to: CGPoint(x: w * 0.9560, y: h * 0.3141), control1: CGPoint(x: w * 0.9570, y: h * 0.3245), control2: CGPoint(x: w * 0.9565, y: h * 0.3209))
        p.addCurve(to: CGPoint(x: w * 0.9528, y: h * 0.2930), control1: CGPoint(x: w * 0.9553, y: h * 0.3053), control2: CGPoint(x: w * 0.9549, y: h * 0.3024))
        p.addCurve(to: CGPoint(x: w * 0.9500, y: h * 0.2778), control1: CGPoint(x: w * 0.9518, y: h * 0.2889), control2: CGPoint(x: w * 0.9506, y: h * 0.2821))
        p.addCurve(to: CGPoint(x: w * 0.9474, y: h * 0.2631), control1: CGPoint(x: w * 0.9494, y: h * 0.2734), control2: CGPoint(x: w * 0.9482, y: h * 0.2668))
        p.addCurve(to: CGPoint(x: w * 0.9447, y: h * 0.2485), control1: CGPoint(x: w * 0.9466, y: h * 0.2593), control2: CGPoint(x: w * 0.9453, y: h * 0.2527))
        p.addCurve(to: CGPoint(x: w * 0.9420, y: h * 0.2333), control1: CGPoint(x: w * 0.9440, y: h * 0.2442), control2: CGPoint(x: w * 0.9428, y: h * 0.2374))
        p.addCurve(to: CGPoint(x: w * 0.9396, y: h * 0.2188), control1: CGPoint(x: w * 0.9411, y: h * 0.2292), control2: CGPoint(x: w * 0.9400, y: h * 0.2226))
        p.addCurve(to: CGPoint(x: w * 0.9374, y: h * 0.2062), control1: CGPoint(x: w * 0.9390, y: h * 0.2150), control2: CGPoint(x: w * 0.9381, y: h * 0.2092))
        p.addCurve(to: CGPoint(x: w * 0.9334, y: h * 0.1840), control1: CGPoint(x: w * 0.9358, y: h * 0.1989), control2: CGPoint(x: w * 0.9345, y: h * 0.1917))
        p.addCurve(to: CGPoint(x: w * 0.9183, y: h * 0.1326), control1: CGPoint(x: w * 0.9319, y: h * 0.1741), control2: CGPoint(x: w * 0.9262, y: h * 0.1546))
        p.addCurve(to: CGPoint(x: w * 0.9133, y: h * 0.1168), control1: CGPoint(x: w * 0.9168, y: h * 0.1284), control2: CGPoint(x: w * 0.9145, y: h * 0.1213))
        p.addCurve(to: CGPoint(x: w * 0.9054, y: h * 0.0953), control1: CGPoint(x: w * 0.9106, y: h * 0.1077), control2: CGPoint(x: w * 0.9096, y: h * 0.1047))
        p.addCurve(to: CGPoint(x: w * 0.9008, y: h * 0.0840), control1: CGPoint(x: w * 0.9039, y: h * 0.0917), control2: CGPoint(x: w * 0.9018, y: h * 0.0866))
        p.addCurve(to: CGPoint(x: w * 0.8958, y: h * 0.0717), control1: CGPoint(x: w * 0.8999, y: h * 0.0815), control2: CGPoint(x: w * 0.8976, y: h * 0.0759))
        p.addCurve(to: CGPoint(x: w * 0.8907, y: h * 0.0591), control1: CGPoint(x: w * 0.8939, y: h * 0.0675), control2: CGPoint(x: w * 0.8916, y: h * 0.0618))
        p.addCurve(to: CGPoint(x: w * 0.8866, y: h * 0.0473), control1: CGPoint(x: w * 0.8898, y: h * 0.0563), control2: CGPoint(x: w * 0.8879, y: h * 0.0511))
        p.addCurve(to: CGPoint(x: w * 0.8647, y: h * 0.0256), control1: CGPoint(x: w * 0.8814, y: h * 0.0322), control2: CGPoint(x: w * 0.8766, y: h * 0.0275))
        p.addCurve(to: CGPoint(x: w * 0.8527, y: h * 0.0235), control1: CGPoint(x: w * 0.8619, y: h * 0.0252), control2: CGPoint(x: w * 0.8565, y: h * 0.0242))
        p.addCurve(to: CGPoint(x: w * 0.7972, y: h * 0.0187), control1: CGPoint(x: w * 0.8355, y: h * 0.0200), control2: CGPoint(x: w * 0.8196, y: h * 0.0186))
        p.addCurve(to: CGPoint(x: w * 0.7542, y: h * 0.0206), control1: CGPoint(x: w * 0.7773, y: h * 0.0188), control2: CGPoint(x: w * 0.7591, y: h * 0.0196))
        p.addCurve(to: CGPoint(x: w * 0.7446, y: h * 0.0220), control1: CGPoint(x: w * 0.7521, y: h * 0.0211), control2: CGPoint(x: w * 0.7478, y: h * 0.0217))
        p.addCurve(to: CGPoint(x: w * 0.7278, y: h * 0.0272), control1: CGPoint(x: w * 0.7373, y: h * 0.0228), control2: CGPoint(x: w * 0.7348, y: h * 0.0235))
        p.addCurve(to: CGPoint(x: w * 0.7008, y: h * 0.0319), control1: CGPoint(x: w * 0.7187, y: h * 0.0320), control2: CGPoint(x: w * 0.7117, y: h * 0.0332))
        p.addCurve(to: CGPoint(x: w * 0.6670, y: h * 0.0640), control1: CGPoint(x: w * 0.6696, y: h * 0.0281), control2: CGPoint(x: w * 0.6651, y: h * 0.0324))
        p.addCurve(to: CGPoint(x: w * 0.6675, y: h * 0.2994), control1: CGPoint(x: w * 0.6678, y: h * 0.0762), control2: CGPoint(x: w * 0.6682, y: h * 0.2870))
        p.addCurve(to: CGPoint(x: w * 0.6376, y: h * 0.3385), control1: CGPoint(x: w * 0.6659, y: h * 0.3270), control2: CGPoint(x: w * 0.6558, y: h * 0.3403))
        p.addCurve(to: CGPoint(x: w * 0.6177, y: h * 0.3320), control1: CGPoint(x: w * 0.6217, y: h * 0.3369), control2: CGPoint(x: w * 0.6205, y: h * 0.3366))
        p.addCurve(to: CGPoint(x: w * 0.6144, y: h * 0.2198), control1: CGPoint(x: w * 0.6142, y: h * 0.3265), control2: CGPoint(x: w * 0.6145, y: h * 0.3360))
        p.addCurve(to: CGPoint(x: w * 0.6181, y: h * 0.0964), control1: CGPoint(x: w * 0.6143, y: h * 0.0992), control2: CGPoint(x: w * 0.6140, y: h * 0.1079))
        p.addCurve(to: CGPoint(x: w * 0.6182, y: h * 0.0828), control1: CGPoint(x: w * 0.6205, y: h * 0.0900), control2: CGPoint(x: w * 0.6205, y: h * 0.0890))
        p.addCurve(to: CGPoint(x: w * 0.6143, y: h * 0.0426), control1: CGPoint(x: w * 0.6146, y: h * 0.0731), control2: CGPoint(x: w * 0.6143, y: h * 0.0704))
        p.addCurve(to: CGPoint(x: w * 0.6030, y: h * 0.0007), control1: CGPoint(x: w * 0.6143, y: h * 0.0072), control2: CGPoint(x: w * 0.6131, y: h * 0.0027))
        p.addCurve(to: CGPoint(x: w * 0.3847, y: h * 0.0007), control1: CGPoint(x: w * 0.5998, y: h * 0.0000), control2: CGPoint(x: w * 0.3879, y: h * 0.0001))
        p.closeSubpath()
        return p
    }
}

/// Nintendo Switch Pro Controller silhouette (traced from product photo)
struct NintendoProBodyShape: Shape {
    static let aspectRatio: CGFloat = 1.3939

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.2834, y: h * 0.0031))
        p.addCurve(to: CGPoint(x: w * 0.2731, y: h * 0.0043), control1: CGPoint(x: w * 0.2810, y: h * 0.0034), control2: CGPoint(x: w * 0.2763, y: h * 0.0039))
        p.addCurve(to: CGPoint(x: w * 0.1362, y: h * 0.0673), control1: CGPoint(x: w * 0.2025, y: h * 0.0128), control2: CGPoint(x: w * 0.1694, y: h * 0.0279))
        p.addCurve(to: CGPoint(x: w * 0.1144, y: h * 0.1093), control1: CGPoint(x: w * 0.1311, y: h * 0.0734), control2: CGPoint(x: w * 0.1239, y: h * 0.0872))
        p.addCurve(to: CGPoint(x: w * 0.1092, y: h * 0.1187), control1: CGPoint(x: w * 0.1122, y: h * 0.1144), control2: CGPoint(x: w * 0.1107, y: h * 0.1171))
        p.addCurve(to: CGPoint(x: w * 0.1054, y: h * 0.1227), control1: CGPoint(x: w * 0.1081, y: h * 0.1199), control2: CGPoint(x: w * 0.1064, y: h * 0.1216))
        p.addCurve(to: CGPoint(x: w * 0.0882, y: h * 0.1542), control1: CGPoint(x: w * 0.1036, y: h * 0.1248), control2: CGPoint(x: w * 0.0913, y: h * 0.1474))
        p.addCurve(to: CGPoint(x: w * 0.0656, y: h * 0.2585), control1: CGPoint(x: w * 0.0831, y: h * 0.1656), control2: CGPoint(x: w * 0.0726, y: h * 0.2142))
        p.addCurve(to: CGPoint(x: w * 0.0583, y: h * 0.3090), control1: CGPoint(x: w * 0.0593, y: h * 0.2983), control2: CGPoint(x: w * 0.0585, y: h * 0.3034))
        p.addCurve(to: CGPoint(x: w * 0.0557, y: h * 0.3295), control1: CGPoint(x: w * 0.0581, y: h * 0.3122), control2: CGPoint(x: w * 0.0569, y: h * 0.3214))
        p.addCurve(to: CGPoint(x: w * 0.0332, y: h * 0.4987), control1: CGPoint(x: w * 0.0481, y: h * 0.3786), control2: CGPoint(x: w * 0.0426, y: h * 0.4198))
        p.addCurve(to: CGPoint(x: w * 0.0254, y: h * 0.5628), control1: CGPoint(x: w * 0.0296, y: h * 0.5289), control2: CGPoint(x: w * 0.0261, y: h * 0.5578))
        p.addCurve(to: CGPoint(x: w * 0.0064, y: h * 0.8473), control1: CGPoint(x: w * 0.0060, y: h * 0.7139), control2: CGPoint(x: w * 0.0000, y: h * 0.8026))
        p.addCurve(to: CGPoint(x: w * 0.1460, y: h * 0.9398), control1: CGPoint(x: w * 0.0212, y: h * 0.9501), control2: CGPoint(x: w * 0.0965, y: h * 1.0000))
        p.addCurve(to: CGPoint(x: w * 0.2074, y: h * 0.8007), control1: CGPoint(x: w * 0.1615, y: h * 0.9208), control2: CGPoint(x: w * 0.1817, y: h * 0.8752))
        p.addCurve(to: CGPoint(x: w * 0.2759, y: h * 0.6824), control1: CGPoint(x: w * 0.2413, y: h * 0.7025), control2: CGPoint(x: w * 0.2490, y: h * 0.6892))
        p.addCurve(to: CGPoint(x: w * 0.7219, y: h * 0.6816), control1: CGPoint(x: w * 0.2815, y: h * 0.6811), control2: CGPoint(x: w * 0.7120, y: h * 0.6802))
        p.addCurve(to: CGPoint(x: w * 0.8005, y: h * 0.8177), control1: CGPoint(x: w * 0.7514, y: h * 0.6857), control2: CGPoint(x: w * 0.7586, y: h * 0.6983))
        p.addCurve(to: CGPoint(x: w * 0.8832, y: h * 0.9610), control1: CGPoint(x: w * 0.8357, y: h * 0.9178), control2: CGPoint(x: w * 0.8524, y: h * 0.9467))
        p.addCurve(to: CGPoint(x: w * 0.9946, y: h * 0.8478), control1: CGPoint(x: w * 0.9304, y: h * 0.9827), control2: CGPoint(x: w * 0.9826, y: h * 0.9297))
        p.addCurve(to: CGPoint(x: w * 0.9878, y: h * 0.6610), control1: CGPoint(x: w * 1.0000, y: h * 0.8113), control2: CGPoint(x: w * 0.9976, y: h * 0.7449))
        p.addCurve(to: CGPoint(x: w * 0.9852, y: h * 0.6381), control1: CGPoint(x: w * 0.9872, y: h * 0.6555), control2: CGPoint(x: w * 0.9861, y: h * 0.6453))
        p.addCurve(to: CGPoint(x: w * 0.9749, y: h * 0.5523), control1: CGPoint(x: w * 0.9832, y: h * 0.6208), control2: CGPoint(x: w * 0.9779, y: h * 0.5761))
        p.addCurve(to: CGPoint(x: w * 0.9683, y: h * 0.4974), control1: CGPoint(x: w * 0.9737, y: h * 0.5419), control2: CGPoint(x: w * 0.9707, y: h * 0.5171))
        p.addCurve(to: CGPoint(x: w * 0.9556, y: h * 0.3956), control1: CGPoint(x: w * 0.9624, y: h * 0.4474), control2: CGPoint(x: w * 0.9584, y: h * 0.4152))
        p.addCurve(to: CGPoint(x: w * 0.9444, y: h * 0.3194), control1: CGPoint(x: w * 0.9517, y: h * 0.3680), control2: CGPoint(x: w * 0.9452, y: h * 0.3238))
        p.addCurve(to: CGPoint(x: w * 0.9435, y: h * 0.3093), control1: CGPoint(x: w * 0.9441, y: h * 0.3180), control2: CGPoint(x: w * 0.9437, y: h * 0.3134))
        p.addCurve(to: CGPoint(x: w * 0.9359, y: h * 0.2566), control1: CGPoint(x: w * 0.9431, y: h * 0.3015), control2: CGPoint(x: w * 0.9417, y: h * 0.2924))
        p.addCurve(to: CGPoint(x: w * 0.8923, y: h * 0.1181), control1: CGPoint(x: w * 0.9220, y: h * 0.1711), control2: CGPoint(x: w * 0.9125, y: h * 0.1410))
        p.addCurve(to: CGPoint(x: w * 0.8880, y: h * 0.1103), control1: CGPoint(x: w * 0.8909, y: h * 0.1166), control2: CGPoint(x: w * 0.8894, y: h * 0.1137))
        p.addCurve(to: CGPoint(x: w * 0.7411, y: h * 0.0057), control1: CGPoint(x: w * 0.8615, y: h * 0.0450), control2: CGPoint(x: w * 0.8228, y: h * 0.0174))
        p.addCurve(to: CGPoint(x: w * 0.6758, y: h * 0.0147), control1: CGPoint(x: w * 0.7016, y: h * 0.0000), control2: CGPoint(x: w * 0.7005, y: h * 0.0001))
        p.addCurve(to: CGPoint(x: w * 0.6449, y: h * 0.0221), control1: CGPoint(x: w * 0.6612, y: h * 0.0233), control2: CGPoint(x: w * 0.6626, y: h * 0.0230))
        p.addCurve(to: CGPoint(x: w * 0.6090, y: h * 0.0207), control1: CGPoint(x: w * 0.6368, y: h * 0.0217), control2: CGPoint(x: w * 0.6206, y: h * 0.0211))
        p.addCurve(to: CGPoint(x: w * 0.5792, y: h * 0.0197), control1: CGPoint(x: w * 0.5974, y: h * 0.0204), control2: CGPoint(x: w * 0.5840, y: h * 0.0199))
        p.addCurve(to: CGPoint(x: w * 0.4491, y: h * 0.0193), control1: CGPoint(x: w * 0.5598, y: h * 0.0188), control2: CGPoint(x: w * 0.4948, y: h * 0.0187))
        p.addCurve(to: CGPoint(x: w * 0.3562, y: h * 0.0221), control1: CGPoint(x: w * 0.4022, y: h * 0.0200), control2: CGPoint(x: w * 0.3867, y: h * 0.0205))
        p.addCurve(to: CGPoint(x: w * 0.3268, y: h * 0.0153), control1: CGPoint(x: w * 0.3391, y: h * 0.0230), control2: CGPoint(x: w * 0.3400, y: h * 0.0232))
        p.addCurve(to: CGPoint(x: w * 0.2834, y: h * 0.0031), control1: CGPoint(x: w * 0.3048, y: h * 0.0022), control2: CGPoint(x: w * 0.3005, y: h * 0.0010))
        p.closeSubpath()
        return p
    }
}

/// Steam Controller silhouette (traced from product photo)
struct SteamControllerBodyShape: Shape {
    static let aspectRatio: CGFloat = 1.4624

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.7331, y: h * 0.0078))
        p.addCurve(to: CGPoint(x: w * 0.7205, y: h * 0.0123), control1: CGPoint(x: w * 0.7301, y: h * 0.0086), control2: CGPoint(x: w * 0.7245, y: h * 0.0107))
        p.addCurve(to: CGPoint(x: w * 0.6843, y: h * 0.0160), control1: CGPoint(x: w * 0.7092, y: h * 0.0172), control2: CGPoint(x: w * 0.7059, y: h * 0.0175))
        p.addCurve(to: CGPoint(x: w * 0.5553, y: h * 0.0126), control1: CGPoint(x: w * 0.6361, y: h * 0.0121), control2: CGPoint(x: w * 0.5680, y: h * 0.0104))
        p.addCurve(to: CGPoint(x: w * 0.5207, y: h * 0.0152), control1: CGPoint(x: w * 0.5485, y: h * 0.0139), control2: CGPoint(x: w * 0.5330, y: h * 0.0150))
        p.addCurve(to: CGPoint(x: w * 0.4755, y: h * 0.0166), control1: CGPoint(x: w * 0.5084, y: h * 0.0155), control2: CGPoint(x: w * 0.4881, y: h * 0.0161))
        p.addCurve(to: CGPoint(x: w * 0.4286, y: h * 0.0180), control1: CGPoint(x: w * 0.4629, y: h * 0.0172), control2: CGPoint(x: w * 0.4418, y: h * 0.0179))
        p.addCurve(to: CGPoint(x: w * 0.4002, y: h * 0.0214), control1: CGPoint(x: w * 0.4083, y: h * 0.0183), control2: CGPoint(x: w * 0.4039, y: h * 0.0190))
        p.addCurve(to: CGPoint(x: w * 0.3855, y: h * 0.0230), control1: CGPoint(x: w * 0.3965, y: h * 0.0238), control2: CGPoint(x: w * 0.3943, y: h * 0.0239))
        p.addCurve(to: CGPoint(x: w * 0.3664, y: h * 0.0220), control1: CGPoint(x: w * 0.3798, y: h * 0.0222), control2: CGPoint(x: w * 0.3712, y: h * 0.0219))
        p.addCurve(to: CGPoint(x: w * 0.3113, y: h * 0.0191), control1: CGPoint(x: w * 0.3434, y: h * 0.0230), control2: CGPoint(x: w * 0.3165, y: h * 0.0215))
        p.addCurve(to: CGPoint(x: w * 0.2998, y: h * 0.0174), control1: CGPoint(x: w * 0.3092, y: h * 0.0182), control2: CGPoint(x: w * 0.3041, y: h * 0.0174))
        p.addCurve(to: CGPoint(x: w * 0.2857, y: h * 0.0150), control1: CGPoint(x: w * 0.2957, y: h * 0.0174), control2: CGPoint(x: w * 0.2893, y: h * 0.0163))
        p.addCurve(to: CGPoint(x: w * 0.2668, y: h * 0.0169), control1: CGPoint(x: w * 0.2764, y: h * 0.0118), control2: CGPoint(x: w * 0.2738, y: h * 0.0120))
        p.addCurve(to: CGPoint(x: w * 0.2393, y: h * 0.0190), control1: CGPoint(x: w * 0.2584, y: h * 0.0227), control2: CGPoint(x: w * 0.2527, y: h * 0.0231))
        p.addCurve(to: CGPoint(x: w * 0.1668, y: h * 0.0487), control1: CGPoint(x: w * 0.2117, y: h * 0.0102), control2: CGPoint(x: w * 0.1851, y: h * 0.0212))
        p.addCurve(to: CGPoint(x: w * 0.0986, y: h * 0.2439), control1: CGPoint(x: w * 0.1281, y: h * 0.1066), control2: CGPoint(x: w * 0.1247, y: h * 0.1160))
        p.addCurve(to: CGPoint(x: w * 0.1450, y: h * 0.9949), control1: CGPoint(x: w * 0.0000, y: h * 0.7261), control2: CGPoint(x: w * 0.0156, y: h * 0.9780))
        p.addCurve(to: CGPoint(x: w * 0.2153, y: h * 0.9150), control1: CGPoint(x: w * 0.1840, y: h * 1.0000), control2: CGPoint(x: w * 0.2022, y: h * 0.9794))
        p.addCurve(to: CGPoint(x: w * 0.2768, y: h * 0.7803), control1: CGPoint(x: w * 0.2325, y: h * 0.8301), control2: CGPoint(x: w * 0.2501, y: h * 0.7917))
        p.addCurve(to: CGPoint(x: w * 0.7232, y: h * 0.7803), control1: CGPoint(x: w * 0.2933, y: h * 0.7733), control2: CGPoint(x: w * 0.7067, y: h * 0.7733))
        p.addCurve(to: CGPoint(x: w * 0.7847, y: h * 0.9150), control1: CGPoint(x: w * 0.7499, y: h * 0.7917), control2: CGPoint(x: w * 0.7675, y: h * 0.8301))
        p.addCurve(to: CGPoint(x: w * 0.8550, y: h * 0.9949), control1: CGPoint(x: w * 0.7978, y: h * 0.9794), control2: CGPoint(x: w * 0.8160, y: h * 1.0000))
        p.addCurve(to: CGPoint(x: w * 0.9014, y: h * 0.2439), control1: CGPoint(x: w * 0.9844, y: h * 0.9781), control2: CGPoint(x: w * 1.0000, y: h * 0.7258))
        p.addCurve(to: CGPoint(x: w * 0.8332, y: h * 0.0487), control1: CGPoint(x: w * 0.8751, y: h * 0.1155), control2: CGPoint(x: w * 0.8721, y: h * 0.1067))
        p.addCurve(to: CGPoint(x: w * 0.7331, y: h * 0.0078), control1: CGPoint(x: w * 0.8152, y: h * 0.0215), control2: CGPoint(x: w * 0.7622, y: h * 0.0000))
        p.closeSubpath()
        return p
    }
}

// MARK: - Shared Components

struct BatteryView: View {
    let level: Float
    let state: GCDeviceBattery.State
    
    // Xbox controllers on macOS often report 0.0 with unknown state when data is unavailable
    private var isUnknown: Bool {
		!ControllerBatteryDisplayPolicy.isKnown(level: level, state: state)
    }

    private var percentage: Int? {
		ControllerBatteryDisplayPolicy.percentage(level: level, state: state)
    }
    
    var body: some View {
        HStack(spacing: 2) {
            if state == .charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
            }
            
            ZStack(alignment: .leading) {
                // Battery outline
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.primary.opacity(0.4), lineWidth: 1)
                    .frame(width: 30, height: 14)
                
                // Empty track background
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 28, height: 12)
                    .padding(.leading, 1)

                // Fill
                if !isUnknown {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(batteryColor)
                            .frame(width: max(2, 28 * CGFloat(level)), height: 12)
                        
						Text("\(percentage ?? 0)%")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 0)
                            .frame(width: 28, alignment: .center)
                    }
                    .padding(.leading, 1)
                } else {
                    // Unknown level
                    Text("?")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 14, alignment: .center)
                }
            }
            
            // Battery tip
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(0.4))
                .frame(width: 2, height: 4)
        }
		.help(percentage.map { "Battery: \($0)%" } ?? "Battery level unavailable (common macOS limitation for Xbox controllers)")
		.accessibilityLabel(percentage.map { "Battery: \($0) percent" } ?? "Battery unavailable")
    }
    
    private var batteryColor: Color {
        if state == .charging { return .green }
        if level > 0.6 { return .green }
        if level > 0.2 { return .orange }
        return .red
    }
}
