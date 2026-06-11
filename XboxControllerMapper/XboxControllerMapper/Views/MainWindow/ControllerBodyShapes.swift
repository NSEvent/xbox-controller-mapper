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
    static let aspectRatio: CGFloat = 1.5708

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.2760, y: h * 0.0623))
        p.addCurve(to: CGPoint(x: w * 0.2619, y: h * 0.1094), control1: CGPoint(x: w * 0.2654, y: h * 0.0677), control2: CGPoint(x: w * 0.2618, y: h * 0.0801))
        p.addCurve(to: CGPoint(x: w * 0.2496, y: h * 0.1252), control1: CGPoint(x: w * 0.2620, y: h * 0.1350), control2: CGPoint(x: w * 0.2600, y: h * 0.1377))
        p.addCurve(to: CGPoint(x: w * 0.2022, y: h * 0.0874), control1: CGPoint(x: w * 0.2332, y: h * 0.1056), control2: CGPoint(x: w * 0.2185, y: h * 0.0939))
        p.addCurve(to: CGPoint(x: w * 0.0597, y: h * 0.3541), control1: CGPoint(x: w * 0.1017, y: h * 0.0475), control2: CGPoint(x: w * 0.0191, y: h * 0.2019))
        p.addCurve(to: CGPoint(x: w * 0.0616, y: h * 0.3831), control1: CGPoint(x: w * 0.0642, y: h * 0.3714), control2: CGPoint(x: w * 0.0645, y: h * 0.3759))
        p.addCurve(to: CGPoint(x: w * 0.0577, y: h * 0.4039), control1: CGPoint(x: w * 0.0578, y: h * 0.3925), control2: CGPoint(x: w * 0.0577, y: h * 0.3932))
        p.addCurve(to: CGPoint(x: w * 0.0588, y: h * 0.4227), control1: CGPoint(x: w * 0.0577, y: h * 0.4108), control2: CGPoint(x: w * 0.0580, y: h * 0.4164))
        p.addCurve(to: CGPoint(x: w * 0.0608, y: h * 0.4389), control1: CGPoint(x: w * 0.0594, y: h * 0.4276), control2: CGPoint(x: w * 0.0603, y: h * 0.4349))
        p.addCurve(to: CGPoint(x: w * 0.0637, y: h * 0.4546), control1: CGPoint(x: w * 0.0612, y: h * 0.4428), control2: CGPoint(x: w * 0.0625, y: h * 0.4499))
        p.addCurve(to: CGPoint(x: w * 0.0642, y: h * 0.4795), control1: CGPoint(x: w * 0.0663, y: h * 0.4655), control2: CGPoint(x: w * 0.0664, y: h * 0.4700))
        p.addCurve(to: CGPoint(x: w * 0.0618, y: h * 0.4945), control1: CGPoint(x: w * 0.0633, y: h * 0.4831), control2: CGPoint(x: w * 0.0623, y: h * 0.4899))
        p.addCurve(to: CGPoint(x: w * 0.0521, y: h * 0.5328), control1: CGPoint(x: w * 0.0606, y: h * 0.5075), control2: CGPoint(x: w * 0.0571, y: h * 0.5214))
        p.addCurve(to: CGPoint(x: w * 0.0485, y: h * 0.5437), control1: CGPoint(x: w * 0.0508, y: h * 0.5358), control2: CGPoint(x: w * 0.0492, y: h * 0.5407))
        p.addCurve(to: CGPoint(x: w * 0.0432, y: h * 0.5586), control1: CGPoint(x: w * 0.0470, y: h * 0.5514), control2: CGPoint(x: w * 0.0463, y: h * 0.5531))
        p.addCurve(to: CGPoint(x: w * 0.0385, y: h * 0.5707), control1: CGPoint(x: w * 0.0412, y: h * 0.5620), control2: CGPoint(x: w * 0.0399, y: h * 0.5656))
        p.addCurve(to: CGPoint(x: w * 0.0240, y: h * 0.6006), control1: CGPoint(x: w * 0.0364, y: h * 0.5787), control2: CGPoint(x: w * 0.0315, y: h * 0.5888))
        p.addCurve(to: CGPoint(x: w * 0.0189, y: h * 0.6167), control1: CGPoint(x: w * 0.0189, y: h * 0.6086), control2: CGPoint(x: w * 0.0189, y: h * 0.6087))
        p.addCurve(to: CGPoint(x: w * 0.0147, y: h * 0.6318), control1: CGPoint(x: w * 0.0189, y: h * 0.6245), control2: CGPoint(x: w * 0.0187, y: h * 0.6254))
        p.addCurve(to: CGPoint(x: w * 0.0028, y: h * 0.7016), control1: CGPoint(x: w * 0.0065, y: h * 0.6451), control2: CGPoint(x: w * 0.0011, y: h * 0.6766))
        p.addCurve(to: CGPoint(x: w * 0.0023, y: h * 0.7340), control1: CGPoint(x: w * 0.0036, y: h * 0.7147), control2: CGPoint(x: w * 0.0035, y: h * 0.7264))
        p.addCurve(to: CGPoint(x: w * 0.0007, y: h * 0.7717), control1: CGPoint(x: w * 0.0008, y: h * 0.7436), control2: CGPoint(x: w * 0.0000, y: h * 0.7636))
        p.addCurve(to: CGPoint(x: w * 0.0018, y: h * 0.7917), control1: CGPoint(x: w * 0.0010, y: h * 0.7752), control2: CGPoint(x: w * 0.0015, y: h * 0.7842))
        p.addCurve(to: CGPoint(x: w * 0.0121, y: h * 0.8309), control1: CGPoint(x: w * 0.0025, y: h * 0.8109), control2: CGPoint(x: w * 0.0027, y: h * 0.8116))
        p.addCurve(to: CGPoint(x: w * 0.0167, y: h * 0.8448), control1: CGPoint(x: w * 0.0146, y: h * 0.8360), control2: CGPoint(x: w * 0.0156, y: h * 0.8387))
        p.addCurve(to: CGPoint(x: w * 0.0200, y: h * 0.8715), control1: CGPoint(x: w * 0.0183, y: h * 0.8520), control2: CGPoint(x: w * 0.0187, y: h * 0.8556))
        p.addCurve(to: CGPoint(x: w * 0.0224, y: h * 0.8861), control1: CGPoint(x: w * 0.0203, y: h * 0.8753), control2: CGPoint(x: w * 0.0214, y: h * 0.8819))
        p.addCurve(to: CGPoint(x: w * 0.0249, y: h * 0.9016), control1: CGPoint(x: w * 0.0233, y: h * 0.8903), control2: CGPoint(x: w * 0.0245, y: h * 0.8973))
        p.addCurve(to: CGPoint(x: w * 0.0319, y: h * 0.9337), control1: CGPoint(x: w * 0.0260, y: h * 0.9127), control2: CGPoint(x: w * 0.0278, y: h * 0.9208))
        p.addCurve(to: CGPoint(x: w * 0.0384, y: h * 0.9601), control1: CGPoint(x: w * 0.0352, y: h * 0.9440), control2: CGPoint(x: w * 0.0360, y: h * 0.9476))
        p.addCurve(to: CGPoint(x: w * 0.1138, y: h * 0.9872), control1: CGPoint(x: w * 0.0430, y: h * 0.9846), control2: CGPoint(x: w * 0.0857, y: h * 1.0000))
        p.addCurve(to: CGPoint(x: w * 0.1845, y: h * 0.8794), control1: CGPoint(x: w * 0.1421, y: h * 0.9743), control2: CGPoint(x: w * 0.1652, y: h * 0.9392))
        p.addCurve(to: CGPoint(x: w * 0.1937, y: h * 0.8524), control1: CGPoint(x: w * 0.1884, y: h * 0.8675), control2: CGPoint(x: w * 0.1925, y: h * 0.8553))
        p.addCurve(to: CGPoint(x: w * 0.2301, y: h * 0.7032), control1: CGPoint(x: w * 0.2019, y: h * 0.8313), control2: CGPoint(x: w * 0.2203, y: h * 0.7560))
        p.addCurve(to: CGPoint(x: w * 0.2353, y: h * 0.6783), control1: CGPoint(x: w * 0.2318, y: h * 0.6940), control2: CGPoint(x: w * 0.2341, y: h * 0.6828))
        p.addCurve(to: CGPoint(x: w * 0.2389, y: h * 0.6615), control1: CGPoint(x: w * 0.2365, y: h * 0.6739), control2: CGPoint(x: w * 0.2381, y: h * 0.6663))
        p.addCurve(to: CGPoint(x: w * 0.2569, y: h * 0.6252), control1: CGPoint(x: w * 0.2417, y: h * 0.6448), control2: CGPoint(x: w * 0.2481, y: h * 0.6320))
        p.addCurve(to: CGPoint(x: w * 0.2760, y: h * 0.6324), control1: CGPoint(x: w * 0.2625, y: h * 0.6209), control2: CGPoint(x: w * 0.2645, y: h * 0.6217))
        p.addCurve(to: CGPoint(x: w * 0.3505, y: h * 0.6557), control1: CGPoint(x: w * 0.2994, y: h * 0.6541), control2: CGPoint(x: w * 0.3283, y: h * 0.6631))
        p.addCurve(to: CGPoint(x: w * 0.3939, y: h * 0.6236), control1: CGPoint(x: w * 0.3673, y: h * 0.6500), control2: CGPoint(x: w * 0.3811, y: h * 0.6398))
        p.addCurve(to: CGPoint(x: w * 0.4215, y: h * 0.6140), control1: CGPoint(x: w * 0.4014, y: h * 0.6140), control2: CGPoint(x: w * 0.4000, y: h * 0.6145))
        p.addCurve(to: CGPoint(x: w * 0.4467, y: h * 0.6147), control1: CGPoint(x: w * 0.4354, y: h * 0.6137), control2: CGPoint(x: w * 0.4416, y: h * 0.6138))
        p.addCurve(to: CGPoint(x: w * 0.4715, y: h * 0.6171), control1: CGPoint(x: w * 0.4638, y: h * 0.6176), control2: CGPoint(x: w * 0.4657, y: h * 0.6178))
        p.addCurve(to: CGPoint(x: w * 0.5285, y: h * 0.6171), control1: CGPoint(x: w * 0.4791, y: h * 0.6163), control2: CGPoint(x: w * 0.5209, y: h * 0.6163))
        p.addCurve(to: CGPoint(x: w * 0.5533, y: h * 0.6147), control1: CGPoint(x: w * 0.5343, y: h * 0.6178), control2: CGPoint(x: w * 0.5362, y: h * 0.6176))
        p.addCurve(to: CGPoint(x: w * 0.5785, y: h * 0.6140), control1: CGPoint(x: w * 0.5584, y: h * 0.6138), control2: CGPoint(x: w * 0.5646, y: h * 0.6137))
        p.addCurve(to: CGPoint(x: w * 0.6061, y: h * 0.6236), control1: CGPoint(x: w * 0.6000, y: h * 0.6145), control2: CGPoint(x: w * 0.5986, y: h * 0.6140))
        p.addCurve(to: CGPoint(x: w * 0.7240, y: h * 0.6324), control1: CGPoint(x: w * 0.6396, y: h * 0.6661), control2: CGPoint(x: w * 0.6841, y: h * 0.6695))
        p.addCurve(to: CGPoint(x: w * 0.7431, y: h * 0.6252), control1: CGPoint(x: w * 0.7355, y: h * 0.6217), control2: CGPoint(x: w * 0.7375, y: h * 0.6209))
        p.addCurve(to: CGPoint(x: w * 0.7611, y: h * 0.6615), control1: CGPoint(x: w * 0.7519, y: h * 0.6320), control2: CGPoint(x: w * 0.7583, y: h * 0.6448))
        p.addCurve(to: CGPoint(x: w * 0.7647, y: h * 0.6783), control1: CGPoint(x: w * 0.7619, y: h * 0.6663), control2: CGPoint(x: w * 0.7635, y: h * 0.6739))
        p.addCurve(to: CGPoint(x: w * 0.7699, y: h * 0.7032), control1: CGPoint(x: w * 0.7659, y: h * 0.6828), control2: CGPoint(x: w * 0.7682, y: h * 0.6940))
        p.addCurve(to: CGPoint(x: w * 0.8063, y: h * 0.8524), control1: CGPoint(x: w * 0.7797, y: h * 0.7560), control2: CGPoint(x: w * 0.7981, y: h * 0.8313))
        p.addCurve(to: CGPoint(x: w * 0.8155, y: h * 0.8794), control1: CGPoint(x: w * 0.8075, y: h * 0.8553), control2: CGPoint(x: w * 0.8116, y: h * 0.8675))
        p.addCurve(to: CGPoint(x: w * 0.8862, y: h * 0.9872), control1: CGPoint(x: w * 0.8348, y: h * 0.9392), control2: CGPoint(x: w * 0.8579, y: h * 0.9743))
        p.addCurve(to: CGPoint(x: w * 0.9616, y: h * 0.9601), control1: CGPoint(x: w * 0.9143, y: h * 1.0000), control2: CGPoint(x: w * 0.9570, y: h * 0.9846))
        p.addCurve(to: CGPoint(x: w * 0.9681, y: h * 0.9337), control1: CGPoint(x: w * 0.9640, y: h * 0.9476), control2: CGPoint(x: w * 0.9648, y: h * 0.9440))
        p.addCurve(to: CGPoint(x: w * 0.9751, y: h * 0.9016), control1: CGPoint(x: w * 0.9722, y: h * 0.9208), control2: CGPoint(x: w * 0.9740, y: h * 0.9127))
        p.addCurve(to: CGPoint(x: w * 0.9776, y: h * 0.8861), control1: CGPoint(x: w * 0.9755, y: h * 0.8973), control2: CGPoint(x: w * 0.9767, y: h * 0.8903))
        p.addCurve(to: CGPoint(x: w * 0.9800, y: h * 0.8715), control1: CGPoint(x: w * 0.9786, y: h * 0.8819), control2: CGPoint(x: w * 0.9797, y: h * 0.8753))
        p.addCurve(to: CGPoint(x: w * 0.9833, y: h * 0.8448), control1: CGPoint(x: w * 0.9813, y: h * 0.8556), control2: CGPoint(x: w * 0.9817, y: h * 0.8520))
        p.addCurve(to: CGPoint(x: w * 0.9879, y: h * 0.8309), control1: CGPoint(x: w * 0.9844, y: h * 0.8387), control2: CGPoint(x: w * 0.9854, y: h * 0.8360))
        p.addCurve(to: CGPoint(x: w * 0.9982, y: h * 0.7917), control1: CGPoint(x: w * 0.9973, y: h * 0.8116), control2: CGPoint(x: w * 0.9975, y: h * 0.8109))
        p.addCurve(to: CGPoint(x: w * 0.9993, y: h * 0.7717), control1: CGPoint(x: w * 0.9985, y: h * 0.7842), control2: CGPoint(x: w * 0.9990, y: h * 0.7752))
        p.addCurve(to: CGPoint(x: w * 0.9977, y: h * 0.7340), control1: CGPoint(x: w * 1.0000, y: h * 0.7636), control2: CGPoint(x: w * 0.9992, y: h * 0.7436))
        p.addCurve(to: CGPoint(x: w * 0.9972, y: h * 0.7016), control1: CGPoint(x: w * 0.9965, y: h * 0.7264), control2: CGPoint(x: w * 0.9964, y: h * 0.7147))
        p.addCurve(to: CGPoint(x: w * 0.9853, y: h * 0.6318), control1: CGPoint(x: w * 0.9989, y: h * 0.6766), control2: CGPoint(x: w * 0.9935, y: h * 0.6451))
        p.addCurve(to: CGPoint(x: w * 0.9811, y: h * 0.6167), control1: CGPoint(x: w * 0.9813, y: h * 0.6254), control2: CGPoint(x: w * 0.9811, y: h * 0.6245))
        p.addCurve(to: CGPoint(x: w * 0.9760, y: h * 0.6006), control1: CGPoint(x: w * 0.9811, y: h * 0.6087), control2: CGPoint(x: w * 0.9811, y: h * 0.6086))
        p.addCurve(to: CGPoint(x: w * 0.9615, y: h * 0.5707), control1: CGPoint(x: w * 0.9685, y: h * 0.5888), control2: CGPoint(x: w * 0.9636, y: h * 0.5787))
        p.addCurve(to: CGPoint(x: w * 0.9568, y: h * 0.5586), control1: CGPoint(x: w * 0.9601, y: h * 0.5656), control2: CGPoint(x: w * 0.9588, y: h * 0.5620))
        p.addCurve(to: CGPoint(x: w * 0.9515, y: h * 0.5437), control1: CGPoint(x: w * 0.9537, y: h * 0.5531), control2: CGPoint(x: w * 0.9530, y: h * 0.5514))
        p.addCurve(to: CGPoint(x: w * 0.9479, y: h * 0.5328), control1: CGPoint(x: w * 0.9508, y: h * 0.5407), control2: CGPoint(x: w * 0.9492, y: h * 0.5358))
        p.addCurve(to: CGPoint(x: w * 0.9382, y: h * 0.4945), control1: CGPoint(x: w * 0.9429, y: h * 0.5214), control2: CGPoint(x: w * 0.9394, y: h * 0.5075))
        p.addCurve(to: CGPoint(x: w * 0.9358, y: h * 0.4795), control1: CGPoint(x: w * 0.9377, y: h * 0.4899), control2: CGPoint(x: w * 0.9367, y: h * 0.4831))
        p.addCurve(to: CGPoint(x: w * 0.9363, y: h * 0.4546), control1: CGPoint(x: w * 0.9336, y: h * 0.4700), control2: CGPoint(x: w * 0.9337, y: h * 0.4655))
        p.addCurve(to: CGPoint(x: w * 0.9392, y: h * 0.4389), control1: CGPoint(x: w * 0.9375, y: h * 0.4499), control2: CGPoint(x: w * 0.9388, y: h * 0.4428))
        p.addCurve(to: CGPoint(x: w * 0.9412, y: h * 0.4227), control1: CGPoint(x: w * 0.9397, y: h * 0.4349), control2: CGPoint(x: w * 0.9406, y: h * 0.4276))
        p.addCurve(to: CGPoint(x: w * 0.9423, y: h * 0.4039), control1: CGPoint(x: w * 0.9420, y: h * 0.4164), control2: CGPoint(x: w * 0.9423, y: h * 0.4108))
        p.addCurve(to: CGPoint(x: w * 0.9384, y: h * 0.3831), control1: CGPoint(x: w * 0.9423, y: h * 0.3932), control2: CGPoint(x: w * 0.9422, y: h * 0.3925))
        p.addCurve(to: CGPoint(x: w * 0.9403, y: h * 0.3541), control1: CGPoint(x: w * 0.9355, y: h * 0.3759), control2: CGPoint(x: w * 0.9358, y: h * 0.3714))
        p.addCurve(to: CGPoint(x: w * 0.7504, y: h * 0.1252), control1: CGPoint(x: w * 0.9911, y: h * 0.1639), control2: CGPoint(x: w * 0.8551, y: h * 0.0000))
        p.addCurve(to: CGPoint(x: w * 0.7381, y: h * 0.1094), control1: CGPoint(x: w * 0.7400, y: h * 0.1377), control2: CGPoint(x: w * 0.7380, y: h * 0.1350))
        p.addCurve(to: CGPoint(x: w * 0.7359, y: h * 0.0795), control1: CGPoint(x: w * 0.7382, y: h * 0.0916), control2: CGPoint(x: w * 0.7378, y: h * 0.0860))
        p.addCurve(to: CGPoint(x: w * 0.7019, y: h * 0.0770), control1: CGPoint(x: w * 0.7291, y: h * 0.0564), control2: CGPoint(x: w * 0.7091, y: h * 0.0549))
        p.addCurve(to: CGPoint(x: w * 0.6858, y: h * 0.0893), control1: CGPoint(x: w * 0.6977, y: h * 0.0901), control2: CGPoint(x: w * 0.6939, y: h * 0.0930))
        p.addCurve(to: CGPoint(x: w * 0.6786, y: h * 0.0884), control1: CGPoint(x: w * 0.6836, y: h * 0.0883), control2: CGPoint(x: w * 0.6818, y: h * 0.0881))
        p.addCurve(to: CGPoint(x: w * 0.6699, y: h * 0.0869), control1: CGPoint(x: w * 0.6752, y: h * 0.0889), control2: CGPoint(x: w * 0.6737, y: h * 0.0886))
        p.addCurve(to: CGPoint(x: w * 0.6600, y: h * 0.0841), control1: CGPoint(x: w * 0.6673, y: h * 0.0859), control2: CGPoint(x: w * 0.6629, y: h * 0.0846))
        p.addCurve(to: CGPoint(x: w * 0.3400, y: h * 0.0841), control1: CGPoint(x: w * 0.6458, y: h * 0.0818), control2: CGPoint(x: w * 0.3542, y: h * 0.0818))
        p.addCurve(to: CGPoint(x: w * 0.3301, y: h * 0.0869), control1: CGPoint(x: w * 0.3371, y: h * 0.0846), control2: CGPoint(x: w * 0.3327, y: h * 0.0859))
        p.addCurve(to: CGPoint(x: w * 0.3214, y: h * 0.0884), control1: CGPoint(x: w * 0.3263, y: h * 0.0886), control2: CGPoint(x: w * 0.3248, y: h * 0.0889))
        p.addCurve(to: CGPoint(x: w * 0.3142, y: h * 0.0893), control1: CGPoint(x: w * 0.3182, y: h * 0.0881), control2: CGPoint(x: w * 0.3164, y: h * 0.0883))
        p.addCurve(to: CGPoint(x: w * 0.2981, y: h * 0.0770), control1: CGPoint(x: w * 0.3061, y: h * 0.0930), control2: CGPoint(x: w * 0.3023, y: h * 0.0901))
        p.addCurve(to: CGPoint(x: w * 0.2760, y: h * 0.0623), control1: CGPoint(x: w * 0.2941, y: h * 0.0646), control2: CGPoint(x: w * 0.2843, y: h * 0.0581))
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
