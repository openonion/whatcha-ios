"""Generate a fixture using the Android reference's actual compiled Wire and Identity."""
from pathlib import Path
import subprocess
import sys

android = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('../whatcha-android-wechat')
cache = Path.home() / '.gradle/caches/modules-2/files-2.1'
patterns = [
    'org.bouncycastle/bcprov-jdk18on/1.78.1/**/*.jar',
    'org.jetbrains.kotlin/kotlin-stdlib/2.0.21/**/*.jar',
    'org.jetbrains.kotlinx/kotlinx-serialization-json-jvm/1.7.3/**/*.jar',
    'org.jetbrains.kotlinx/kotlinx-serialization-core-jvm/1.7.3/**/*.jar',
]
classpath = ':'.join([str(android / 'app/build/tmp/kotlin-classes/debug')] +
                     [str(next(cache.glob(pattern))) for pattern in patterns])
Path('build/vector').mkdir(parents=True, exist_ok=True)
subprocess.run(['javac', '-encoding', 'UTF-8', '-cp', classpath, '-d', 'build/vector',
                'tools/AndroidWireVector.java'], check=True)
arguments = [sys.argv[2]] if len(sys.argv) > 2 else []
result = subprocess.run(['java', '-Dfile.encoding=UTF-8', '-Dstdout.encoding=UTF-8',
                         '-cp', 'build/vector:' + classpath, 'AndroidWireVector'] + arguments,
                        check=True, capture_output=True, encoding='utf-8')
if not arguments:
    Path('Tests/WhatchaCoreTests/android-wire-vector.jsonl').write_text(result.stdout)
print(result.stdout)
