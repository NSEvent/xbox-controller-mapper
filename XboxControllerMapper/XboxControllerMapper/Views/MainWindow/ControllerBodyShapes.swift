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
    static let aspectRatio: CGFloat = 1.6067

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.3157, y: h * 0.0008))
        p.addCurve(to: CGPoint(x: w * 0.3050, y: h * 0.0135), control1: CGPoint(x: w * 0.3105, y: h * 0.0020), control2: CGPoint(x: w * 0.3081, y: h * 0.0048))
        p.addCurve(to: CGPoint(x: w * 0.2861, y: h * 0.0265), control1: CGPoint(x: w * 0.3007, y: h * 0.0250), control2: CGPoint(x: w * 0.2977, y: h * 0.0271))
        p.addCurve(to: CGPoint(x: w * 0.2700, y: h * 0.0219), control1: CGPoint(x: w * 0.2781, y: h * 0.0260), control2: CGPoint(x: w * 0.2756, y: h * 0.0253))
        p.addCurve(to: CGPoint(x: w * 0.2545, y: h * 0.0173), control1: CGPoint(x: w * 0.2641, y: h * 0.0184), control2: CGPoint(x: w * 0.2625, y: h * 0.0179))
        p.addCurve(to: CGPoint(x: w * 0.2427, y: h * 0.0159), control1: CGPoint(x: w * 0.2507, y: h * 0.0170), control2: CGPoint(x: w * 0.2454, y: h * 0.0164))
        p.addCurve(to: CGPoint(x: w * 0.1617, y: h * 0.0162), control1: CGPoint(x: w * 0.2241, y: h * 0.0127), control2: CGPoint(x: w * 0.1952, y: h * 0.0128))
        p.addCurve(to: CGPoint(x: w * 0.1417, y: h * 0.0189), control1: CGPoint(x: w * 0.1507, y: h * 0.0173), control2: CGPoint(x: w * 0.1458, y: h * 0.0179))
        p.addCurve(to: CGPoint(x: w * 0.1331, y: h * 0.0203), control1: CGPoint(x: w * 0.1404, y: h * 0.0192), control2: CGPoint(x: w * 0.1366, y: h * 0.0198))
        p.addCurve(to: CGPoint(x: w * 0.1130, y: h * 0.0438), control1: CGPoint(x: w * 0.1206, y: h * 0.0219), control2: CGPoint(x: w * 0.1194, y: h * 0.0234))
        p.addCurve(to: CGPoint(x: w * 0.1038, y: h * 0.0683), control1: CGPoint(x: w * 0.1087, y: h * 0.0574), control2: CGPoint(x: w * 0.1077, y: h * 0.0602))
        p.addCurve(to: CGPoint(x: w * 0.0991, y: h * 0.0796), control1: CGPoint(x: w * 0.1025, y: h * 0.0710), control2: CGPoint(x: w * 0.1004, y: h * 0.0760))
        p.addCurve(to: CGPoint(x: w * 0.0932, y: h * 0.0935), control1: CGPoint(x: w * 0.0978, y: h * 0.0831), control2: CGPoint(x: w * 0.0951, y: h * 0.0893))
        p.addCurve(to: CGPoint(x: w * 0.0784, y: h * 0.1342), control1: CGPoint(x: w * 0.0893, y: h * 0.1017), control2: CGPoint(x: w * 0.0806, y: h * 0.1258))
        p.addCurve(to: CGPoint(x: w * 0.0760, y: h * 0.1436), control1: CGPoint(x: w * 0.0777, y: h * 0.1368), control2: CGPoint(x: w * 0.0766, y: h * 0.1410))
        p.addCurve(to: CGPoint(x: w * 0.0719, y: h * 0.1582), control1: CGPoint(x: w * 0.0753, y: h * 0.1461), control2: CGPoint(x: w * 0.0735, y: h * 0.1528))
        p.addCurve(to: CGPoint(x: w * 0.0652, y: h * 0.1857), control1: CGPoint(x: w * 0.0689, y: h * 0.1686), control2: CGPoint(x: w * 0.0681, y: h * 0.1719))
        p.addCurve(to: CGPoint(x: w * 0.0625, y: h * 0.1979), control1: CGPoint(x: w * 0.0642, y: h * 0.1903), control2: CGPoint(x: w * 0.0631, y: h * 0.1957))
        p.addCurve(to: CGPoint(x: w * 0.0601, y: h * 0.2092), control1: CGPoint(x: w * 0.0620, y: h * 0.2000), control2: CGPoint(x: w * 0.0610, y: h * 0.2051))
        p.addCurve(to: CGPoint(x: w * 0.0574, y: h * 0.2221), control1: CGPoint(x: w * 0.0593, y: h * 0.2133), control2: CGPoint(x: w * 0.0581, y: h * 0.2191))
        p.addCurve(to: CGPoint(x: w * 0.0552, y: h * 0.2374), control1: CGPoint(x: w * 0.0566, y: h * 0.2257), control2: CGPoint(x: w * 0.0558, y: h * 0.2311))
        p.addCurve(to: CGPoint(x: w * 0.0527, y: h * 0.2539), control1: CGPoint(x: w * 0.0545, y: h * 0.2442), control2: CGPoint(x: w * 0.0537, y: h * 0.2490))
        p.addCurve(to: CGPoint(x: w * 0.0493, y: h * 0.2751), control1: CGPoint(x: w * 0.0509, y: h * 0.2617), control2: CGPoint(x: w * 0.0503, y: h * 0.2656))
        p.addCurve(to: CGPoint(x: w * 0.0469, y: h * 0.2897), control1: CGPoint(x: w * 0.0489, y: h * 0.2789), control2: CGPoint(x: w * 0.0479, y: h * 0.2851))
        p.addCurve(to: CGPoint(x: w * 0.0437, y: h * 0.3136), control1: CGPoint(x: w * 0.0453, y: h * 0.2975), control2: CGPoint(x: w * 0.0448, y: h * 0.3012))
        p.addCurve(to: CGPoint(x: w * 0.0413, y: h * 0.3285), control1: CGPoint(x: w * 0.0433, y: h * 0.3176), control2: CGPoint(x: w * 0.0425, y: h * 0.3226))
        p.addCurve(to: CGPoint(x: w * 0.0385, y: h * 0.3448), control1: CGPoint(x: w * 0.0403, y: h * 0.3334), control2: CGPoint(x: w * 0.0390, y: h * 0.3408))
        p.addCurve(to: CGPoint(x: w * 0.0366, y: h * 0.3578), control1: CGPoint(x: w * 0.0380, y: h * 0.3489), control2: CGPoint(x: w * 0.0371, y: h * 0.3548))
        p.addCurve(to: CGPoint(x: w * 0.0337, y: h * 0.3772), control1: CGPoint(x: w * 0.0349, y: h * 0.3666), control2: CGPoint(x: w * 0.0346, y: h * 0.3683))
        p.addCurve(to: CGPoint(x: w * 0.0312, y: h * 0.3940), control1: CGPoint(x: w * 0.0332, y: h * 0.3824), control2: CGPoint(x: w * 0.0322, y: h * 0.3889))
        p.addCurve(to: CGPoint(x: w * 0.0287, y: h * 0.4099), control1: CGPoint(x: w * 0.0301, y: h * 0.3991), control2: CGPoint(x: w * 0.0292, y: h * 0.4054))
        p.addCurve(to: CGPoint(x: w * 0.0256, y: h * 0.4309), control1: CGPoint(x: w * 0.0279, y: h * 0.4186), control2: CGPoint(x: w * 0.0275, y: h * 0.4214))
        p.addCurve(to: CGPoint(x: w * 0.0230, y: h * 0.4493), control1: CGPoint(x: w * 0.0247, y: h * 0.4354), control2: CGPoint(x: w * 0.0238, y: h * 0.4417))
        p.addCurve(to: CGPoint(x: w * 0.0198, y: h * 0.4744), control1: CGPoint(x: w * 0.0224, y: h * 0.4557), control2: CGPoint(x: w * 0.0209, y: h * 0.4670))
        p.addCurve(to: CGPoint(x: w * 0.0169, y: h * 0.4954), control1: CGPoint(x: w * 0.0187, y: h * 0.4819), control2: CGPoint(x: w * 0.0174, y: h * 0.4913))
        p.addCurve(to: CGPoint(x: w * 0.0143, y: h * 0.5111), control1: CGPoint(x: w * 0.0164, y: h * 0.4995), control2: CGPoint(x: w * 0.0152, y: h * 0.5065))
        p.addCurve(to: CGPoint(x: w * 0.0114, y: h * 0.5357), control1: CGPoint(x: w * 0.0120, y: h * 0.5224), control2: CGPoint(x: w * 0.0120, y: h * 0.5228))
        p.addCurve(to: CGPoint(x: w * 0.0083, y: h * 0.5625), control1: CGPoint(x: w * 0.0108, y: h * 0.5489), control2: CGPoint(x: w * 0.0104, y: h * 0.5521))
        p.addCurve(to: CGPoint(x: w * 0.0057, y: h * 0.5921), control1: CGPoint(x: w * 0.0060, y: h * 0.5734), control2: CGPoint(x: w * 0.0058, y: h * 0.5762))
        p.addCurve(to: CGPoint(x: w * 0.0030, y: h * 0.6261), control1: CGPoint(x: w * 0.0057, y: h * 0.6109), control2: CGPoint(x: w * 0.0055, y: h * 0.6143))
        p.addCurve(to: CGPoint(x: w * 0.0003, y: h * 0.7187), control1: CGPoint(x: w * 0.0000, y: h * 0.6403), control2: CGPoint(x: w * 0.0002, y: h * 0.6352))
        p.addCurve(to: CGPoint(x: w * 0.0003, y: h * 0.8062), control1: CGPoint(x: w * 0.0003, y: h * 0.7592), control2: CGPoint(x: w * 0.0003, y: h * 0.7985))
        p.addCurve(to: CGPoint(x: w * 0.0028, y: h * 0.8354), control1: CGPoint(x: w * 0.0001, y: h * 0.8220), control2: CGPoint(x: w * 0.0003, y: h * 0.8245))
        p.addCurve(to: CGPoint(x: w * 0.0057, y: h * 0.8505), control1: CGPoint(x: w * 0.0037, y: h * 0.8390), control2: CGPoint(x: w * 0.0050, y: h * 0.8458))
        p.addCurve(to: CGPoint(x: w * 0.0305, y: h * 0.9234), control1: CGPoint(x: w * 0.0084, y: h * 0.8671), control2: CGPoint(x: w * 0.0209, y: h * 0.9039))
        p.addCurve(to: CGPoint(x: w * 0.1549, y: h * 0.9590), control1: CGPoint(x: w * 0.0611, y: h * 0.9855), control2: CGPoint(x: w * 0.1118, y: h * 1.0000))
        p.addCurve(to: CGPoint(x: w * 0.1872, y: h * 0.9095), control1: CGPoint(x: w * 0.1666, y: h * 0.9478), control2: CGPoint(x: w * 0.1764, y: h * 0.9328))
        p.addCurve(to: CGPoint(x: w * 0.2119, y: h * 0.8451), control1: CGPoint(x: w * 0.1962, y: h * 0.8902), control2: CGPoint(x: w * 0.1989, y: h * 0.8830))
        p.addCurve(to: CGPoint(x: w * 0.2186, y: h * 0.8272), control1: CGPoint(x: w * 0.2134, y: h * 0.8407), control2: CGPoint(x: w * 0.2164, y: h * 0.8326))
        p.addCurve(to: CGPoint(x: w * 0.2270, y: h * 0.8004), control1: CGPoint(x: w * 0.2234, y: h * 0.8156), control2: CGPoint(x: w * 0.2243, y: h * 0.8126))
        p.addCurve(to: CGPoint(x: w * 0.2326, y: h * 0.7778), control1: CGPoint(x: w * 0.2295, y: h * 0.7885), control2: CGPoint(x: w * 0.2299, y: h * 0.7871))
        p.addCurve(to: CGPoint(x: w * 0.2368, y: h * 0.7612), control1: CGPoint(x: w * 0.2339, y: h * 0.7733), control2: CGPoint(x: w * 0.2358, y: h * 0.7659))
        p.addCurve(to: CGPoint(x: w * 0.2415, y: h * 0.7411), control1: CGPoint(x: w * 0.2379, y: h * 0.7565), control2: CGPoint(x: w * 0.2400, y: h * 0.7474))
        p.addCurve(to: CGPoint(x: w * 0.2467, y: h * 0.7190), control1: CGPoint(x: w * 0.2431, y: h * 0.7347), control2: CGPoint(x: w * 0.2454, y: h * 0.7248))
        p.addCurve(to: CGPoint(x: w * 0.2506, y: h * 0.7025), control1: CGPoint(x: w * 0.2480, y: h * 0.7132), control2: CGPoint(x: w * 0.2497, y: h * 0.7058))
        p.addCurve(to: CGPoint(x: w * 0.2534, y: h * 0.6890), control1: CGPoint(x: w * 0.2515, y: h * 0.6991), control2: CGPoint(x: w * 0.2527, y: h * 0.6930))
        p.addCurve(to: CGPoint(x: w * 0.2891, y: h * 0.6477), control1: CGPoint(x: w * 0.2620, y: h * 0.6367), control2: CGPoint(x: w * 0.2691, y: h * 0.6285))
        p.addCurve(to: CGPoint(x: w * 0.3052, y: h * 0.6606), control1: CGPoint(x: w * 0.2977, y: h * 0.6560), control2: CGPoint(x: w * 0.3009, y: h * 0.6585))
        p.addCurve(to: CGPoint(x: w * 0.3129, y: h * 0.6644), control1: CGPoint(x: w * 0.3069, y: h * 0.6614), control2: CGPoint(x: w * 0.3104, y: h * 0.6631))
        p.addCurve(to: CGPoint(x: w * 0.3665, y: h * 0.6663), control1: CGPoint(x: w * 0.3253, y: h * 0.6708), control2: CGPoint(x: w * 0.3572, y: h * 0.6719))
        p.addCurve(to: CGPoint(x: w * 0.3752, y: h * 0.6614), control1: CGPoint(x: w * 0.3681, y: h * 0.6654), control2: CGPoint(x: w * 0.3720, y: h * 0.6632))
        p.addCurve(to: CGPoint(x: w * 0.4080, y: h * 0.6345), control1: CGPoint(x: w * 0.3849, y: h * 0.6560), control2: CGPoint(x: w * 0.3980, y: h * 0.6453))
        p.addCurve(to: CGPoint(x: w * 0.4314, y: h * 0.6255), control1: CGPoint(x: w * 0.4152, y: h * 0.6268), control2: CGPoint(x: w * 0.4168, y: h * 0.6262))
        p.addCurve(to: CGPoint(x: w * 0.4518, y: h * 0.6175), control1: CGPoint(x: w * 0.4455, y: h * 0.6249), control2: CGPoint(x: w * 0.4466, y: h * 0.6246))
        p.addCurve(to: CGPoint(x: w * 0.5021, y: h * 0.6064), control1: CGPoint(x: w * 0.4605, y: h * 0.6058), control2: CGPoint(x: w * 0.4590, y: h * 0.6061))
        p.addCurve(to: CGPoint(x: w * 0.5467, y: h * 0.6167), control1: CGPoint(x: w * 0.5410, y: h * 0.6066), control2: CGPoint(x: w * 0.5388, y: h * 0.6061))
        p.addCurve(to: CGPoint(x: w * 0.5692, y: h * 0.6261), control1: CGPoint(x: w * 0.5529, y: h * 0.6251), control2: CGPoint(x: w * 0.5540, y: h * 0.6255))
        p.addCurve(to: CGPoint(x: w * 0.5925, y: h * 0.6361), control1: CGPoint(x: w * 0.5839, y: h * 0.6266), control2: CGPoint(x: w * 0.5837, y: h * 0.6265))
        p.addCurve(to: CGPoint(x: w * 0.6225, y: h * 0.6597), control1: CGPoint(x: w * 0.6003, y: h * 0.6445), control2: CGPoint(x: w * 0.6136, y: h * 0.6550))
        p.addCurve(to: CGPoint(x: w * 0.6311, y: h * 0.6647), control1: CGPoint(x: w * 0.6253, y: h * 0.6612), control2: CGPoint(x: w * 0.6291, y: h * 0.6634))
        p.addCurve(to: CGPoint(x: w * 0.6494, y: h * 0.6695), control1: CGPoint(x: w * 0.6381, y: h * 0.6693), control2: CGPoint(x: w * 0.6380, y: h * 0.6693))
        p.addCurve(to: CGPoint(x: w * 0.6870, y: h * 0.6628), control1: CGPoint(x: w * 0.6684, y: h * 0.6699), control2: CGPoint(x: w * 0.6733, y: h * 0.6691))
        p.addCurve(to: CGPoint(x: w * 0.7101, y: h * 0.6475), control1: CGPoint(x: w * 0.6976, y: h * 0.6580), control2: CGPoint(x: w * 0.6973, y: h * 0.6581))
        p.addCurve(to: CGPoint(x: w * 0.7265, y: h * 0.6382), control1: CGPoint(x: w * 0.7210, y: h * 0.6384), control2: CGPoint(x: w * 0.7233, y: h * 0.6371))
        p.addCurve(to: CGPoint(x: w * 0.7417, y: h * 0.6660), control1: CGPoint(x: w * 0.7330, y: h * 0.6404), control2: CGPoint(x: w * 0.7388, y: h * 0.6511))
        p.addCurve(to: CGPoint(x: w * 0.7446, y: h * 0.6788), control1: CGPoint(x: w * 0.7423, y: h * 0.6691), control2: CGPoint(x: w * 0.7436, y: h * 0.6748))
        p.addCurve(to: CGPoint(x: w * 0.7528, y: h * 0.7187), control1: CGPoint(x: w * 0.7468, y: h * 0.6874), control2: CGPoint(x: w * 0.7516, y: h * 0.7107))
        p.addCurve(to: CGPoint(x: w * 0.7553, y: h * 0.7309), control1: CGPoint(x: w * 0.7533, y: h * 0.7219), control2: CGPoint(x: w * 0.7544, y: h * 0.7274))
        p.addCurve(to: CGPoint(x: w * 0.7586, y: h * 0.7458), control1: CGPoint(x: w * 0.7561, y: h * 0.7344), control2: CGPoint(x: w * 0.7576, y: h * 0.7411))
        p.addCurve(to: CGPoint(x: w * 0.7660, y: h * 0.7738), control1: CGPoint(x: w * 0.7608, y: h * 0.7559), control2: CGPoint(x: w * 0.7628, y: h * 0.7636))
        p.addCurve(to: CGPoint(x: w * 0.7738, y: h * 0.8043), control1: CGPoint(x: w * 0.7686, y: h * 0.7821), control2: CGPoint(x: w * 0.7717, y: h * 0.7944))
        p.addCurve(to: CGPoint(x: w * 0.7802, y: h * 0.8243), control1: CGPoint(x: w * 0.7756, y: h * 0.8125), control2: CGPoint(x: w * 0.7768, y: h * 0.8161))
        p.addCurve(to: CGPoint(x: w * 0.7896, y: h * 0.8505), control1: CGPoint(x: w * 0.7834, y: h * 0.8319), control2: CGPoint(x: w * 0.7836, y: h * 0.8321))
        p.addCurve(to: CGPoint(x: w * 0.9139, y: h * 0.9790), control1: CGPoint(x: w * 0.8237, y: h * 0.9538), control2: CGPoint(x: w * 0.8641, y: h * 0.9956))
        p.addCurve(to: CGPoint(x: w * 0.9938, y: h * 0.8495), control1: CGPoint(x: w * 0.9515, y: h * 0.9665), control2: CGPoint(x: w * 0.9864, y: h * 0.9099))
        p.addCurve(to: CGPoint(x: w * 0.9965, y: h * 0.8319), control1: CGPoint(x: w * 0.9945, y: h * 0.8439), control2: CGPoint(x: w * 0.9957, y: h * 0.8359))
        p.addCurve(to: CGPoint(x: w * 0.9996, y: h * 0.7441), control1: CGPoint(x: w * 0.9996, y: h * 0.8170), control2: CGPoint(x: w * 0.9994, y: h * 0.8211))
        p.addCurve(to: CGPoint(x: w * 0.9972, y: h * 0.6280), control1: CGPoint(x: w * 0.9999, y: h * 0.6352), control2: CGPoint(x: w * 1.0000, y: h * 0.6413))
        p.addCurve(to: CGPoint(x: w * 0.9939, y: h * 0.5933), control1: CGPoint(x: w * 0.9946, y: h * 0.6162), control2: CGPoint(x: w * 0.9945, y: h * 0.6148))
        p.addCurve(to: CGPoint(x: w * 0.9917, y: h * 0.5681), control1: CGPoint(x: w * 0.9935, y: h * 0.5789), control2: CGPoint(x: w * 0.9933, y: h * 0.5762))
        p.addCurve(to: CGPoint(x: w * 0.9889, y: h * 0.5436), control1: CGPoint(x: w * 0.9898, y: h * 0.5584), control2: CGPoint(x: w * 0.9895, y: h * 0.5559))
        p.addCurve(to: CGPoint(x: w * 0.9862, y: h * 0.5197), control1: CGPoint(x: w * 0.9884, y: h * 0.5311), control2: CGPoint(x: w * 0.9881, y: h * 0.5285))
        p.addCurve(to: CGPoint(x: w * 0.9835, y: h * 0.4982), control1: CGPoint(x: w * 0.9845, y: h * 0.5117), control2: CGPoint(x: w * 0.9841, y: h * 0.5086))
        p.addCurve(to: CGPoint(x: w * 0.9804, y: h * 0.4759), control1: CGPoint(x: w * 0.9829, y: h * 0.4880), control2: CGPoint(x: w * 0.9826, y: h * 0.4857))
        p.addCurve(to: CGPoint(x: w * 0.9773, y: h * 0.4527), control1: CGPoint(x: w * 0.9788, y: h * 0.4689), control2: CGPoint(x: w * 0.9783, y: h * 0.4648))
        p.addCurve(to: CGPoint(x: w * 0.9749, y: h * 0.4372), control1: CGPoint(x: w * 0.9769, y: h * 0.4478), control2: CGPoint(x: w * 0.9762, y: h * 0.4436))
        p.addCurve(to: CGPoint(x: w * 0.9720, y: h * 0.4201), control1: CGPoint(x: w * 0.9739, y: h * 0.4323), control2: CGPoint(x: w * 0.9725, y: h * 0.4246))
        p.addCurve(to: CGPoint(x: w * 0.9694, y: h * 0.4036), control1: CGPoint(x: w * 0.9714, y: h * 0.4155), control2: CGPoint(x: w * 0.9702, y: h * 0.4081))
        p.addCurve(to: CGPoint(x: w * 0.9675, y: h * 0.3901), control1: CGPoint(x: w * 0.9686, y: h * 0.3990), control2: CGPoint(x: w * 0.9677, y: h * 0.3929))
        p.addCurve(to: CGPoint(x: w * 0.9644, y: h * 0.3652), control1: CGPoint(x: w * 0.9663, y: h * 0.3748), control2: CGPoint(x: w * 0.9661, y: h * 0.3727))
        p.addCurve(to: CGPoint(x: w * 0.9608, y: h * 0.3445), control1: CGPoint(x: w * 0.9621, y: h * 0.3553), control2: CGPoint(x: w * 0.9618, y: h * 0.3536))
        p.addCurve(to: CGPoint(x: w * 0.9591, y: h * 0.3318), control1: CGPoint(x: w * 0.9604, y: h * 0.3402), control2: CGPoint(x: w * 0.9595, y: h * 0.3345))
        p.addCurve(to: CGPoint(x: w * 0.9560, y: h * 0.3104), control1: CGPoint(x: w * 0.9570, y: h * 0.3209), control2: CGPoint(x: w * 0.9565, y: h * 0.3172))
        p.addCurve(to: CGPoint(x: w * 0.9528, y: h * 0.2891), control1: CGPoint(x: w * 0.9553, y: h * 0.3015), control2: CGPoint(x: w * 0.9549, y: h * 0.2986))
        p.addCurve(to: CGPoint(x: w * 0.9500, y: h * 0.2738), control1: CGPoint(x: w * 0.9518, y: h * 0.2851), control2: CGPoint(x: w * 0.9506, y: h * 0.2782))
        p.addCurve(to: CGPoint(x: w * 0.9474, y: h * 0.2590), control1: CGPoint(x: w * 0.9494, y: h * 0.2695), control2: CGPoint(x: w * 0.9482, y: h * 0.2628))
        p.addCurve(to: CGPoint(x: w * 0.9447, y: h * 0.2444), control1: CGPoint(x: w * 0.9466, y: h * 0.2552), control2: CGPoint(x: w * 0.9453, y: h * 0.2486))
        p.addCurve(to: CGPoint(x: w * 0.9420, y: h * 0.2291), control1: CGPoint(x: w * 0.9440, y: h * 0.2401), control2: CGPoint(x: w * 0.9428, y: h * 0.2333))
        p.addCurve(to: CGPoint(x: w * 0.9396, y: h * 0.2145), control1: CGPoint(x: w * 0.9411, y: h * 0.2249), control2: CGPoint(x: w * 0.9400, y: h * 0.2184))
        p.addCurve(to: CGPoint(x: w * 0.9374, y: h * 0.2018), control1: CGPoint(x: w * 0.9390, y: h * 0.2107), control2: CGPoint(x: w * 0.9381, y: h * 0.2049))
        p.addCurve(to: CGPoint(x: w * 0.9334, y: h * 0.1795), control1: CGPoint(x: w * 0.9358, y: h * 0.1946), control2: CGPoint(x: w * 0.9345, y: h * 0.1873))
        p.addCurve(to: CGPoint(x: w * 0.9183, y: h * 0.1279), control1: CGPoint(x: w * 0.9319, y: h * 0.1696), control2: CGPoint(x: w * 0.9262, y: h * 0.1499))
        p.addCurve(to: CGPoint(x: w * 0.9133, y: h * 0.1120), control1: CGPoint(x: w * 0.9168, y: h * 0.1236), control2: CGPoint(x: w * 0.9145, y: h * 0.1165))
        p.addCurve(to: CGPoint(x: w * 0.9054, y: h * 0.0904), control1: CGPoint(x: w * 0.9106, y: h * 0.1029), control2: CGPoint(x: w * 0.9096, y: h * 0.0998))
        p.addCurve(to: CGPoint(x: w * 0.9008, y: h * 0.0790), control1: CGPoint(x: w * 0.9039, y: h * 0.0867), control2: CGPoint(x: w * 0.9018, y: h * 0.0816))
        p.addCurve(to: CGPoint(x: w * 0.8958, y: h * 0.0666), control1: CGPoint(x: w * 0.8999, y: h * 0.0764), control2: CGPoint(x: w * 0.8976, y: h * 0.0709))
        p.addCurve(to: CGPoint(x: w * 0.8907, y: h * 0.0539), control1: CGPoint(x: w * 0.8939, y: h * 0.0624), control2: CGPoint(x: w * 0.8916, y: h * 0.0566))
        p.addCurve(to: CGPoint(x: w * 0.8866, y: h * 0.0421), control1: CGPoint(x: w * 0.8898, y: h * 0.0512), control2: CGPoint(x: w * 0.8879, y: h * 0.0459))
        p.addCurve(to: CGPoint(x: w * 0.8647, y: h * 0.0203), control1: CGPoint(x: w * 0.8814, y: h * 0.0269), control2: CGPoint(x: w * 0.8766, y: h * 0.0222))
        p.addCurve(to: CGPoint(x: w * 0.8527, y: h * 0.0181), control1: CGPoint(x: w * 0.8619, y: h * 0.0199), control2: CGPoint(x: w * 0.8565, y: h * 0.0189))
        p.addCurve(to: CGPoint(x: w * 0.7972, y: h * 0.0133), control1: CGPoint(x: w * 0.8355, y: h * 0.0147), control2: CGPoint(x: w * 0.8196, y: h * 0.0133))
        p.addCurve(to: CGPoint(x: w * 0.7542, y: h * 0.0153), control1: CGPoint(x: w * 0.7773, y: h * 0.0134), control2: CGPoint(x: w * 0.7591, y: h * 0.0142))
        p.addCurve(to: CGPoint(x: w * 0.7446, y: h * 0.0167), control1: CGPoint(x: w * 0.7521, y: h * 0.0157), control2: CGPoint(x: w * 0.7478, y: h * 0.0164))
        p.addCurve(to: CGPoint(x: w * 0.7278, y: h * 0.0219), control1: CGPoint(x: w * 0.7373, y: h * 0.0174), control2: CGPoint(x: w * 0.7348, y: h * 0.0182))
        p.addCurve(to: CGPoint(x: w * 0.6962, y: h * 0.0259), control1: CGPoint(x: w * 0.7182, y: h * 0.0270), control2: CGPoint(x: w * 0.7073, y: h * 0.0284))
        p.addCurve(to: CGPoint(x: w * 0.6827, y: h * 0.0126), control1: CGPoint(x: w * 0.6880, y: h * 0.0241), control2: CGPoint(x: w * 0.6861, y: h * 0.0222))
        p.addCurve(to: CGPoint(x: w * 0.6716, y: h * 0.0007), control1: CGPoint(x: w * 0.6798, y: h * 0.0045), control2: CGPoint(x: w * 0.6773, y: h * 0.0019))
        p.addCurve(to: CGPoint(x: w * 0.3157, y: h * 0.0008), control1: CGPoint(x: w * 0.6679, y: h * 0.0000), control2: CGPoint(x: w * 0.3189, y: h * 0.0001))
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

/// 8BitDo Zero 2 silhouette (traced from top-down product photo)
struct EightBitDoZero2BodyShape: Shape {
    static let aspectRatio: CGFloat = 2.0941

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.6693, y: h * 0.0021))
        p.addCurve(to: CGPoint(x: w * 0.6238, y: h * 0.0034), control1: CGPoint(x: w * 0.6579, y: h * 0.0026), control2: CGPoint(x: w * 0.6375, y: h * 0.0033))
        p.addCurve(to: CGPoint(x: w * 0.5748, y: h * 0.0269), control1: CGPoint(x: w * 0.5890, y: h * 0.0037), control2: CGPoint(x: w * 0.5863, y: h * 0.0050))
        p.addCurve(to: CGPoint(x: w * 0.5243, y: h * 0.0461), control1: CGPoint(x: w * 0.5649, y: h * 0.0457), control2: CGPoint(x: w * 0.5677, y: h * 0.0446))
        p.addCurve(to: CGPoint(x: w * 0.4384, y: h * 0.0492), control1: CGPoint(x: w * 0.5038, y: h * 0.0467), control2: CGPoint(x: w * 0.4652, y: h * 0.0480))
        p.addCurve(to: CGPoint(x: w * 0.3697, y: h * 0.0332), control1: CGPoint(x: w * 0.3776, y: h * 0.0516), control2: CGPoint(x: w * 0.3799, y: h * 0.0521))
        p.addCurve(to: CGPoint(x: w * 0.2371, y: h * 0.0166), control1: CGPoint(x: w * 0.3582, y: h * 0.0117), control2: CGPoint(x: w * 0.3414, y: h * 0.0096))
        p.addCurve(to: CGPoint(x: w * 0.0511, y: h * 0.2336), control1: CGPoint(x: w * 0.1505, y: h * 0.0223), control2: CGPoint(x: w * 0.0933, y: h * 0.0890))
        p.addCurve(to: CGPoint(x: w * 0.0405, y: h * 0.2689), control1: CGPoint(x: w * 0.0482, y: h * 0.2437), control2: CGPoint(x: w * 0.0434, y: h * 0.2594))
        p.addCurve(to: CGPoint(x: w * 0.0065, y: h * 0.5894), control1: CGPoint(x: w * 0.0124, y: h * 0.3605), control2: CGPoint(x: w * 0.0000, y: h * 0.4772))
        p.addCurve(to: CGPoint(x: w * 0.0840, y: h * 0.8864), control1: CGPoint(x: w * 0.0130, y: h * 0.6987), control2: CGPoint(x: w * 0.0436, y: h * 0.8161))
        p.addCurve(to: CGPoint(x: w * 0.1213, y: h * 0.9427), control1: CGPoint(x: w * 0.0930, y: h * 0.9022), control2: CGPoint(x: w * 0.1166, y: h * 0.9377))
        p.addCurve(to: CGPoint(x: w * 0.2146, y: h * 0.9980), control1: CGPoint(x: w * 0.1492, y: h * 0.9720), control2: CGPoint(x: w * 0.1835, y: h * 0.9925))
        p.addCurve(to: CGPoint(x: w * 0.4590, y: h * 0.9948), control1: CGPoint(x: w * 0.2257, y: h * 1.0000), control2: CGPoint(x: w * 0.4417, y: h * 0.9972))
        p.addCurve(to: CGPoint(x: w * 0.4912, y: h * 0.9933), control1: CGPoint(x: w * 0.4646, y: h * 0.9941), control2: CGPoint(x: w * 0.4791, y: h * 0.9933))
        p.addCurve(to: CGPoint(x: w * 0.5398, y: h * 0.9915), control1: CGPoint(x: w * 0.5033, y: h * 0.9932), control2: CGPoint(x: w * 0.5253, y: h * 0.9925))
        p.addCurve(to: CGPoint(x: w * 0.6157, y: h * 0.9883), control1: CGPoint(x: w * 0.5544, y: h * 0.9907), control2: CGPoint(x: w * 0.5885, y: h * 0.9893))
        p.addCurve(to: CGPoint(x: w * 0.7684, y: h * 0.9744), control1: CGPoint(x: w * 0.7528, y: h * 0.9832), control2: CGPoint(x: w * 0.7463, y: h * 0.9837))
        p.addCurve(to: CGPoint(x: w * 0.9105, y: h * 0.2498), control1: CGPoint(x: w * 0.9252, y: h * 0.9082), control2: CGPoint(x: w * 1.0000, y: h * 0.5269))
        p.addCurve(to: CGPoint(x: w * 0.8944, y: h * 0.1997), control1: CGPoint(x: w * 0.9059, y: h * 0.2357), control2: CGPoint(x: w * 0.8986, y: h * 0.2131))
        p.addCurve(to: CGPoint(x: w * 0.7566, y: h * 0.0068), control1: CGPoint(x: w * 0.8610, y: h * 0.0942), control2: CGPoint(x: w * 0.8130, y: h * 0.0270))
        p.addCurve(to: CGPoint(x: w * 0.6693, y: h * 0.0021), control1: CGPoint(x: w * 0.7430, y: h * 0.0020), control2: CGPoint(x: w * 0.7072, y: h * 0.0000))
        p.closeSubpath()
        return p
    }
}


/// 8BitDo Micro silhouette (traced from official front render)
struct EightBitDoMicroBodyShape: Shape {
    static let aspectRatio: CGFloat = 1.7535

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.1641, y: h * 0.0072))
        p.addCurve(to: CGPoint(x: w * 0.1564, y: h * 0.0108), control1: CGPoint(x: w * 0.1634, y: h * 0.0082), control2: CGPoint(x: w * 0.1599, y: h * 0.0099))
        p.addCurve(to: CGPoint(x: w * 0.0160, y: h * 0.1990), control1: CGPoint(x: w * 0.0952, y: h * 0.0277), control2: CGPoint(x: w * 0.0412, y: h * 0.1002))
        p.addCurve(to: CGPoint(x: w * 0.0146, y: h * 0.2277), control1: CGPoint(x: w * 0.0125, y: h * 0.2129), control2: CGPoint(x: w * 0.0123, y: h * 0.2175))
        p.addCurve(to: CGPoint(x: w * 0.0111, y: h * 0.2515), control1: CGPoint(x: w * 0.0165, y: h * 0.2361), control2: CGPoint(x: w * 0.0160, y: h * 0.2393))
        p.addCurve(to: CGPoint(x: w * 0.0047, y: h * 0.2801), control1: CGPoint(x: w * 0.0077, y: h * 0.2601), control2: CGPoint(x: w * 0.0069, y: h * 0.2636))
        p.addCurve(to: CGPoint(x: w * 0.0018, y: h * 0.2969), control1: CGPoint(x: w * 0.0038, y: h * 0.2871), control2: CGPoint(x: w * 0.0025, y: h * 0.2947))
        p.addCurve(to: CGPoint(x: w * 0.0019, y: h * 0.7287), control1: CGPoint(x: w * 0.0000, y: h * 0.3029), control2: CGPoint(x: w * 0.0001, y: h * 0.7227))
        p.addCurve(to: CGPoint(x: w * 0.0048, y: h * 0.7469), control1: CGPoint(x: w * 0.0025, y: h * 0.7308), control2: CGPoint(x: w * 0.0038, y: h * 0.7390))
        p.addCurve(to: CGPoint(x: w * 0.1262, y: h * 0.9750), control1: CGPoint(x: w * 0.0181, y: h * 0.8553), control2: CGPoint(x: w * 0.0654, y: h * 0.9443))
        p.addCurve(to: CGPoint(x: w * 0.3167, y: h * 0.9871), control1: CGPoint(x: w * 0.1504, y: h * 0.9872), control2: CGPoint(x: w * 0.1348, y: h * 0.9862))
        p.addCurve(to: CGPoint(x: w * 0.4833, y: h * 0.9958), control1: CGPoint(x: w * 0.4946, y: h * 0.9879), control2: CGPoint(x: w * 0.4817, y: h * 0.9872))
        p.addCurve(to: CGPoint(x: w * 0.5168, y: h * 0.9958), control1: CGPoint(x: w * 0.4841, y: h * 1.0000), control2: CGPoint(x: w * 0.5160, y: h * 1.0000))
        p.addCurve(to: CGPoint(x: w * 0.6761, y: h * 0.9875), control1: CGPoint(x: w * 0.5184, y: h * 0.9872), control2: CGPoint(x: w * 0.5062, y: h * 0.9878))
        p.addCurve(to: CGPoint(x: w * 0.8546, y: h * 0.9828), control1: CGPoint(x: w * 0.8391, y: h * 0.9874), control2: CGPoint(x: w * 0.8395, y: h * 0.9872))
        p.addCurve(to: CGPoint(x: w * 0.9949, y: h * 0.7479), control1: CGPoint(x: w * 0.9243, y: h * 0.9620), control2: CGPoint(x: w * 0.9794, y: h * 0.8698))
        p.addCurve(to: CGPoint(x: w * 0.9983, y: h * 0.7271), control1: CGPoint(x: w * 0.9962, y: h * 0.7386), control2: CGPoint(x: w * 0.9976, y: h * 0.7293))
        p.addCurve(to: CGPoint(x: w * 0.9983, y: h * 0.2976), control1: CGPoint(x: w * 1.0000, y: h * 0.7211), control2: CGPoint(x: w * 1.0000, y: h * 0.3025))
        p.addCurve(to: CGPoint(x: w * 0.9957, y: h * 0.2829), control1: CGPoint(x: w * 0.9976, y: h * 0.2959), control2: CGPoint(x: w * 0.9965, y: h * 0.2893))
        p.addCurve(to: CGPoint(x: w * 0.9883, y: h * 0.2498), control1: CGPoint(x: w * 0.9936, y: h * 0.2656), control2: CGPoint(x: w * 0.9922, y: h * 0.2594))
        p.addCurve(to: CGPoint(x: w * 0.9856, y: h * 0.2271), control1: CGPoint(x: w * 0.9837, y: h * 0.2384), control2: CGPoint(x: w * 0.9834, y: h * 0.2357))
        p.addCurve(to: CGPoint(x: w * 0.9810, y: h * 0.1891), control1: CGPoint(x: w * 0.9880, y: h * 0.2172), control2: CGPoint(x: w * 0.9874, y: h * 0.2119))
        p.addCurve(to: CGPoint(x: w * 0.8439, y: h * 0.0109), control1: CGPoint(x: w * 0.9545, y: h * 0.0943), control2: CGPoint(x: w * 0.9029, y: h * 0.0274))
        p.addCurve(to: CGPoint(x: w * 0.8359, y: h * 0.0072), control1: CGPoint(x: w * 0.8405, y: h * 0.0099), control2: CGPoint(x: w * 0.8369, y: h * 0.0083))
        p.addCurve(to: CGPoint(x: w * 0.7334, y: h * 0.0090), control1: CGPoint(x: w * 0.8318, y: h * 0.0026), control2: CGPoint(x: w * 0.7346, y: h * 0.0045))
        p.addCurve(to: CGPoint(x: w * 0.7185, y: h * 0.0090), control1: CGPoint(x: w * 0.7281, y: h * 0.0299), control2: CGPoint(x: w * 0.7239, y: h * 0.0299))
        p.addCurve(to: CGPoint(x: w * 0.6805, y: h * 0.0052), control1: CGPoint(x: w * 0.7176, y: h * 0.0052), control2: CGPoint(x: w * 0.7176, y: h * 0.0052))
        p.addCurve(to: CGPoint(x: w * 0.6420, y: h * 0.0202), control1: CGPoint(x: w * 0.6382, y: h * 0.0052), control2: CGPoint(x: w * 0.6431, y: h * 0.0033))
        p.addCurve(to: CGPoint(x: w * 0.6373, y: h * 0.0373), control1: CGPoint(x: w * 0.6413, y: h * 0.0307), control2: CGPoint(x: w * 0.6398, y: h * 0.0365))
        p.addCurve(to: CGPoint(x: w * 0.4316, y: h * 0.0388), control1: CGPoint(x: w * 0.6332, y: h * 0.0389), control2: CGPoint(x: w * 0.4964, y: h * 0.0398))
        p.addCurve(to: CGPoint(x: w * 0.3576, y: h * 0.0155), control1: CGPoint(x: w * 0.3501, y: h * 0.0376), control2: CGPoint(x: w * 0.3598, y: h * 0.0406))
        p.addLine(to: CGPoint(x: w * 0.3566, y: h * 0.0052))
        p.addLine(to: CGPoint(x: w * 0.3197, y: h * 0.0052))
        p.addCurve(to: CGPoint(x: w * 0.2803, y: h * 0.0123), control1: CGPoint(x: w * 0.2827, y: h * 0.0052), control2: CGPoint(x: w * 0.2827, y: h * 0.0052))
        p.addCurve(to: CGPoint(x: w * 0.2678, y: h * 0.0129), control1: CGPoint(x: w * 0.2746, y: h * 0.0293), control2: CGPoint(x: w * 0.2727, y: h * 0.0294))
        p.addCurve(to: CGPoint(x: w * 0.1641, y: h * 0.0072), control1: CGPoint(x: w * 0.2655, y: h * 0.0053), control2: CGPoint(x: w * 0.1696, y: h * 0.0000))
        p.closeSubpath()
        return p
    }
}


/// 8BitDo Lite 2 silhouette (traced from official front render)
struct EightBitDoLite2BodyShape: Shape {
    static let aspectRatio: CGFloat = 1.7967

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.1575, y: h * 0.0068))
        p.addCurve(to: CGPoint(x: w * 0.1473, y: h * 0.0109), control1: CGPoint(x: w * 0.1567, y: h * 0.0077), control2: CGPoint(x: w * 0.1521, y: h * 0.0095))
        p.addCurve(to: CGPoint(x: w * 0.0111, y: h * 0.1872), control1: CGPoint(x: w * 0.0881, y: h * 0.0282), control2: CGPoint(x: w * 0.0371, y: h * 0.0944))
        p.addCurve(to: CGPoint(x: w * 0.0079, y: h * 0.2196), control1: CGPoint(x: w * 0.0058, y: h * 0.2062), control2: CGPoint(x: w * 0.0054, y: h * 0.2111))
        p.addCurve(to: CGPoint(x: w * 0.0085, y: h * 0.2491), control1: CGPoint(x: w * 0.0111, y: h * 0.2302), control2: CGPoint(x: w * 0.0111, y: h * 0.2326))
        p.addCurve(to: CGPoint(x: w * 0.0042, y: h * 0.2805), control1: CGPoint(x: w * 0.0071, y: h * 0.2575), control2: CGPoint(x: w * 0.0052, y: h * 0.2715))
        p.addCurve(to: CGPoint(x: w * 0.0014, y: h * 0.2981), control1: CGPoint(x: w * 0.0031, y: h * 0.2893), control2: CGPoint(x: w * 0.0019, y: h * 0.2972))
        p.addCurve(to: CGPoint(x: w * 0.0017, y: h * 0.7275), control1: CGPoint(x: w * 0.0000, y: h * 0.3006), control2: CGPoint(x: w * 0.0002, y: h * 0.7225))
        p.addCurve(to: CGPoint(x: w * 0.0040, y: h * 0.7436), control1: CGPoint(x: w * 0.0023, y: h * 0.7296), control2: CGPoint(x: w * 0.0033, y: h * 0.7368))
        p.addCurve(to: CGPoint(x: w * 0.1443, y: h * 0.9932), control1: CGPoint(x: w * 0.0171, y: h * 0.8686), control2: CGPoint(x: w * 0.0750, y: h * 0.9718))
        p.addCurve(to: CGPoint(x: w * 0.1512, y: h * 0.9969), control1: CGPoint(x: w * 0.1472, y: h * 0.9940), control2: CGPoint(x: w * 0.1503, y: h * 0.9957))
        p.addCurve(to: CGPoint(x: w * 0.8479, y: h * 0.9974), control1: CGPoint(x: w * 0.1534, y: h * 0.9994), control2: CGPoint(x: w * 0.8465, y: h * 1.0000))
        p.addCurve(to: CGPoint(x: w * 0.8566, y: h * 0.9930), control1: CGPoint(x: w * 0.8484, y: h * 0.9966), control2: CGPoint(x: w * 0.8523, y: h * 0.9946))
        p.addCurve(to: CGPoint(x: w * 0.9948, y: h * 0.7547), control1: CGPoint(x: w * 0.9256, y: h * 0.9682), control2: CGPoint(x: w * 0.9799, y: h * 0.8744))
        p.addCurve(to: CGPoint(x: w * 0.9976, y: h * 0.7370), control1: CGPoint(x: w * 0.9955, y: h * 0.7489), control2: CGPoint(x: w * 0.9968, y: h * 0.7408))
        p.addCurve(to: CGPoint(x: w * 0.9979, y: h * 0.2906), control1: CGPoint(x: w * 0.9997, y: h * 0.7272), control2: CGPoint(x: w * 1.0000, y: h * 0.2978))
        p.addCurve(to: CGPoint(x: w * 0.9956, y: h * 0.2761), control1: CGPoint(x: w * 0.9973, y: h * 0.2883), control2: CGPoint(x: w * 0.9962, y: h * 0.2818))
        p.addCurve(to: CGPoint(x: w * 0.9920, y: h * 0.2514), control1: CGPoint(x: w * 0.9949, y: h * 0.2705), control2: CGPoint(x: w * 0.9933, y: h * 0.2593))
        p.addCurve(to: CGPoint(x: w * 0.9919, y: h * 0.2209), control1: CGPoint(x: w * 0.9891, y: h * 0.2335), control2: CGPoint(x: w * 0.9891, y: h * 0.2319))
        p.addCurve(to: CGPoint(x: w * 0.9879, y: h * 0.1841), control1: CGPoint(x: w * 0.9949, y: h * 0.2097), control2: CGPoint(x: w * 0.9948, y: h * 0.2081))
        p.addCurve(to: CGPoint(x: w * 0.8535, y: h * 0.0111), control1: CGPoint(x: w * 0.9622, y: h * 0.0934), control2: CGPoint(x: w * 0.9118, y: h * 0.0287))
        p.addCurve(to: CGPoint(x: w * 0.8428, y: h * 0.0068), control1: CGPoint(x: w * 0.8485, y: h * 0.0095), control2: CGPoint(x: w * 0.8437, y: h * 0.0075))
        p.addCurve(to: CGPoint(x: w * 0.7744, y: h * 0.0132), control1: CGPoint(x: w * 0.8358, y: h * 0.0000), control2: CGPoint(x: w * 0.7764, y: h * 0.0057))
        p.addCurve(to: CGPoint(x: w * 0.5004, y: h * 0.0265), control1: CGPoint(x: w * 0.7703, y: h * 0.0280), control2: CGPoint(x: w * 0.8031, y: h * 0.0264))
        p.addCurve(to: CGPoint(x: w * 0.2283, y: h * 0.0193), control1: CGPoint(x: w * 0.2140, y: h * 0.0265), control2: CGPoint(x: w * 0.2323, y: h * 0.0270))
        p.addCurve(to: CGPoint(x: w * 0.2253, y: h * 0.0105), control1: CGPoint(x: w * 0.2274, y: h * 0.0173), control2: CGPoint(x: w * 0.2260, y: h * 0.0135))
        p.addCurve(to: CGPoint(x: w * 0.1575, y: h * 0.0068), control1: CGPoint(x: w * 0.2241, y: h * 0.0053), control2: CGPoint(x: w * 0.1623, y: h * 0.0018))
        p.closeSubpath()
        return p
    }
}


/// 8BitDo Lite SE silhouette (traced from official front render)
struct EightBitDoLiteSEBodyShape: Shape {
    static let aspectRatio: CGFloat = 1.8147

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.6360, y: h * 0.0074))
        p.addCurve(to: CGPoint(x: w * 0.6309, y: h * 0.0183), control1: CGPoint(x: w * 0.6356, y: h * 0.0112), control2: CGPoint(x: w * 0.6336, y: h * 0.0155))
        p.addCurve(to: CGPoint(x: w * 0.3938, y: h * 0.0203), control1: CGPoint(x: w * 0.6302, y: h * 0.0191), control2: CGPoint(x: w * 0.5312, y: h * 0.0199))
        p.addCurve(to: CGPoint(x: w * 0.1268, y: h * 0.0346), control1: CGPoint(x: w * 0.1286, y: h * 0.0212), control2: CGPoint(x: w * 0.1520, y: h * 0.0199))
        p.addCurve(to: CGPoint(x: w * 0.0031, y: h * 0.3824), control1: CGPoint(x: w * 0.0459, y: h * 0.0815), control2: CGPoint(x: w * 0.0000, y: h * 0.2105))
        p.addCurve(to: CGPoint(x: w * 0.0031, y: h * 0.5047), control1: CGPoint(x: w * 0.0034, y: h * 0.3973), control2: CGPoint(x: w * 0.0034, y: h * 0.4710))
        p.addCurve(to: CGPoint(x: w * 0.0046, y: h * 0.7095), control1: CGPoint(x: w * 0.0027, y: h * 0.5525), control2: CGPoint(x: w * 0.0038, y: h * 0.6976))
        p.addCurve(to: CGPoint(x: w * 0.1469, y: h * 0.9922), control1: CGPoint(x: w * 0.0148, y: h * 0.8558), control2: CGPoint(x: w * 0.0702, y: h * 0.9656))
        p.addCurve(to: CGPoint(x: w * 0.1572, y: h * 0.9970), control1: CGPoint(x: w * 0.1516, y: h * 0.9937), control2: CGPoint(x: w * 0.1563, y: h * 0.9960))
        p.addCurve(to: CGPoint(x: w * 0.8460, y: h * 0.9970), control1: CGPoint(x: w * 0.1599, y: h * 1.0000), control2: CGPoint(x: w * 0.8434, y: h * 1.0000))
        p.addCurve(to: CGPoint(x: w * 0.8532, y: h * 0.9933), control1: CGPoint(x: w * 0.8469, y: h * 0.9960), control2: CGPoint(x: w * 0.8502, y: h * 0.9943))
        p.addCurve(to: CGPoint(x: w * 0.9950, y: h * 0.7475), control1: CGPoint(x: w * 0.9236, y: h * 0.9714), control2: CGPoint(x: w * 0.9801, y: h * 0.8734))
        p.addCurve(to: CGPoint(x: w * 0.9982, y: h * 0.7259), control1: CGPoint(x: w * 0.9961, y: h * 0.7378), control2: CGPoint(x: w * 0.9976, y: h * 0.7282))
        p.addCurve(to: CGPoint(x: w * 0.9982, y: h * 0.2920), control1: CGPoint(x: w * 1.0000, y: h * 0.7196), control2: CGPoint(x: w * 1.0000, y: h * 0.2983))
        p.addCurve(to: CGPoint(x: w * 0.9955, y: h * 0.2740), control1: CGPoint(x: w * 0.9975, y: h * 0.2896), control2: CGPoint(x: w * 0.9963, y: h * 0.2815))
        p.addCurve(to: CGPoint(x: w * 0.8698, y: h * 0.0310), control1: CGPoint(x: w * 0.9826, y: h * 0.1573), control2: CGPoint(x: w * 0.9333, y: h * 0.0620))
        p.addCurve(to: CGPoint(x: w * 0.7648, y: h * 0.0203), control1: CGPoint(x: w * 0.8489, y: h * 0.0208), control2: CGPoint(x: w * 0.8540, y: h * 0.0212))
        p.addCurve(to: CGPoint(x: w * 0.6785, y: h * 0.0085), control1: CGPoint(x: w * 0.6740, y: h * 0.0195), control2: CGPoint(x: w * 0.6818, y: h * 0.0206))
        p.addCurve(to: CGPoint(x: w * 0.6360, y: h * 0.0074), control1: CGPoint(x: w * 0.6765, y: h * 0.0011), control2: CGPoint(x: w * 0.6370, y: h * 0.0000))
        p.closeSubpath()
        return p
    }
}

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
