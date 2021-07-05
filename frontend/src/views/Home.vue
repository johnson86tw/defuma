<template>
  <div class="font-bold">{{ userDisplayName }}</div>

  <div v-if="userDisplayName">
    <!-- <div>Block number: {{ blockNumber }}</div> -->
    <div>Balance: {{ balance }} ETH</div>
    <div class="font-bold">Pay Interest</div>
    <div>Flow Rate: 38580246913580</div>

    <div class="flex justify-center items-center mb-6">
      <div class="">
        <label class="block text-gray-500 font-bold md:text-right mb-1 md:mb-0 pr-3" for="inline-full-name">
          Loan ID:
        </label>
      </div>
      <div class="">
        <input
          v-model="loanId"
          class="
            bg-gray-200
            appearance-none
            border-2 border-gray-200
            rounded
            w-32
            py-2
            px-4
            text-gray-700
            leading-tight
            focus:outline-none
            focus:bg-white
            focus:border-blue-500
          "
          id="inline-full-name"
          type="text"
        />
      </div>
    </div>

    <div class="m-2">
      <button
        @click="pay"
        class="
          shadow
          bg-blue-500
          hover:bg-blue-400
          focus:shadow-outline
          focus:outline-none
          text-white
          font-bold
          py-2
          px-4
          rounded
        "
        type="button"
      >
        pay
      </button>
    </div>
  </div>
</template>

<script lang="ts">
import { computed, defineComponent, onMounted, ref } from 'vue';
import useDataStore from 'src/store/data';
import useWalletStore from 'src/store/wallet';
import { commify, formatUnits } from 'src/utils/ethers';
import SuperfluidSDK from '@superfluid-finance/js-sdk';
import { Web3Provider } from '@ethersproject/providers';
import { utils } from 'ethers';

// https://stackoverflow.com/questions/65504958/web3-js-extending-the-window-interface-type-definitions
declare global {
  interface Window {
    ethereum: any;
  }
}

export default defineComponent({
  name: 'Home',
  setup() {
    const { lastBlockNumber, lastBlockTimestamp, ethBalance } = useDataStore();
    const { userDisplayName, network } = useWalletStore();
    const abiCoder = utils.defaultAbiCoder;

    let sf: any;
    let user: any;
    let walletAddress: any;

    const details = ref(null);

    const loanId = ref(0);
    const pay = async () => {
      console.log('click pay');
      console.log(loanId.value);

      await sf.cfa.createFlow({
        flowRate: '38580246913580',
        receiver: '0xE7B24CBFa6C3c6AF0817AebCa32c5F56483B07d2', // contract Loan
        sender: walletAddress[0],
        superToken: '0xF2d68898557cCb2Cf4C10c3Ef2B034b2a69DAD00', // goerli fDAIx
        userData: abiCoder.encode(['uint256'], [Number(loanId.value)]),
      });

      details.value = await user.details();
    };

    const getDetails = (user: any) => {
      return new Promise((resolve) => {
        async function print() {
          details.value = await user.details();
          resolve('hello');

          setTimeout(() => {
            print();
          }, 3000);
        }
        print();
      });
    };

    onMounted(async () => {
      sf = new SuperfluidSDK.Framework({
        ethers: new Web3Provider(window.ethereum),
        tokens: ['fDAI'],
      });
      await sf.initialize();

      walletAddress = await window.ethereum.request({
        method: 'eth_requestAccounts',
        params: [
          {
            eth_accounts: {},
          },
        ],
      });

      user = sf.user({
        address: walletAddress[0],
        token: sf.tokens.fDAIx.address,
      });

      getDetails(user);
    });

    const blockNumber = computed(() => commify(lastBlockNumber.value));
    const date = computed(() => new Date(lastBlockTimestamp.value * 1000).toLocaleString());
    const balance = computed(() => (ethBalance.value ? Number(formatUnits(ethBalance.value)).toFixed(4) : 0));
    return { userDisplayName, network, blockNumber, date, balance, formatUnits, loanId, pay, details };
  },
});
</script>
