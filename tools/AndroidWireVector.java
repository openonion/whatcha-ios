// Run against the Android reference's compiled debug classes and its Gradle dependency jars.
// This uses only a deterministic test seed, never the phone's or agent's identity.
import ai.openonion.whatcha.Identity;
import ai.openonion.whatcha.Wire;
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters;
import org.bouncycastle.crypto.signers.Ed25519Signer;
import kotlinx.serialization.json.*;
import ai.openonion.whatcha.WireKt;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;

public class AndroidWireVector {
    public static void main(String[] args) throws Exception {
        byte[] seed = new byte[32];
        for (int i = 0; i < seed.length; i++) seed[i] = (byte) i;
        Ed25519PrivateKeyParameters key = new Ed25519PrivateKeyParameters(seed, 0);
        Identity me = new Identity(key);
        if (args.length > 0) {
            for (String line : Files.readAllLines(Path.of(args[0]), StandardCharsets.UTF_8)) {
                JsonObject frame = (JsonObject) Json.Default.parseToJsonElement(line);
                byte[] payload = WireKt.canonical(frame.get("payload")).getBytes(StandardCharsets.UTF_8);
                String signature = ((JsonPrimitive) frame.get("signature")).getContent();
                Ed25519Signer verifier = new Ed25519Signer();
                verifier.init(false, key.generatePublicKey());
                verifier.update(payload, 0, payload.length);
                if (!verifier.verifySignature(HexFormat.of().parseHex(signature)))
                    throw new AssertionError("Swift signature rejected by Android");
            }
            System.out.println("Verified all Swift frames with Android canonical() and Bouncy Castle");
            return;
        }
        Wire wire = new Wire(me, "0xagent", () -> 1700000000L);
        System.out.println(wire.connect("saved"));
        System.out.println(wire.onboard("test-invite"));
        System.out.println(wire.input("最近忙啥呢", null, null));
    }
}
