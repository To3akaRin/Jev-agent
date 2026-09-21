import asyncio
import sys
import time

from jev_agent.cli import smoke_request
from jev_agent.providers import LayaProvider


class FakeAgent:
    def predict(self, state, questions):
        time.sleep(0.05)
        return {
            "answers": {
                "paste": {
                    "type": "choice",
                    "choice": "c1",
                    "confidence": 0.9,
                    "probabilities": {"c0": 0.02, "c1": 0.94, "c2": 0.02, "none": 0.02},
                }
            }
        }


async def test_laya_timeout_marks_runtime_unusable():
    provider = LayaProvider(timeout_seconds=0.005)
    provider.agent = FakeAgent()
    provider.ready = True
    from jev_agent.prompt import prepare_input

    provider.prepare = prepare_input
    result = await provider.decide(smoke_request("laya"))
    assert result["error"]["code"] == "TIMEOUT"
    assert not provider.ready
    # 等待当前测试替身线程退出；真实桌面将回收进程。
    await asyncio.sleep(0.06)


async def test_local_provider_does_not_import_cloud_sdk():
    import subprocess

    code = "from jev_agent.providers import create_provider; import sys; create_provider('laya'); assert 'typesafe_sdk' not in sys.modules"
    subprocess.run([sys.executable, "-c", code], check=True)
