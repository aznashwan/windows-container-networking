package main_test

import (
	"os"
	"testing"

	"github.com/Microsoft/hcsshim/hcn"
	"github.com/Microsoft/windows-container-networking/test/utilities"
)

func CreateNatTestNetwork() *hcn.HostComputeNetwork {
	ipams := util.GetDefaultIpams()
	return util.CreateTestNetwork("natNet", "Nat", ipams, false)
}

func TestNatCmdAdd(t *testing.T) {
	testNetwork := CreateNatTestNetwork()
    testDualStack := (os.Getenv("TestDualStack") == "1")
    imageToUse := os.Getenv("ImageToUse")
	pt := util.MakeTestStruct(t, testNetwork, "nat", false, false, "", testDualStack, imageToUse)
	pt.RunAll(t)
}
